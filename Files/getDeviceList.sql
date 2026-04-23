##
##	WARNING: please keep the debug version of this file
##	up-to-date when changing something here.
##
use ${NetMRIDB};

##
## Determine IP Address and resident VirtualNetwork of the NetMRI, so we can add it to the list
## If mgmt port is not attached to a VirtualNetwork, dont add it here
##
set @netmriIP:='';
set @netmriVNID:='';
set @netmriDeviceID:=0;

select 
  @netmriIP:=coalesce(ipv4_address, ipv6_address),
  @netmriVNID:=virtual_network_id
from ${ConfigDB}.scan_interfaces
where if_dev = 'eth0' and virtual_network_id is not null and '${excludeEth0IP}' != 'true';

select @netmriDeviceID:=DeviceID
from   ${NetMRIDB}.Device
where  IPAddress = @netmriIP and VirtualNetworkID = @netmriVNID;

##
## Make a copy of the Device table for use by this script to
## prevent locking issues with other processes while making
## joins to it.
##
drop temporary table if exists currentDeviceList;

create temporary table currentDeviceList (
	DeviceID 	bigint,
	IPAddress 	varchar(39),
	InetAddr 	decimal(39,0),
	Type		varchar(32),
	TypeProbability	int,
	Vendor		varchar(50),
	TypeRank	int,
	DiscoveryStatus	char(8),
	FirstOccurrence	bigint,
	VirtualNetworkID bigint
);

insert into currentDeviceList
select DeviceID,
       IPAddress,
       netmri.inet_pton(IPAddress) as InetAddr,
       Type,
       TypeProbability,
       Vendor,
       0 as TypeRank,
       DiscoveryStatus,
       unix_timestamp(FirstOccurrence),
       VirtualNetworkID
from   ${NetMRIDB}.Device
where VirtualNetworkID!= 0;

update currentDeviceList d, ${NetMRIDB}.DeviceType dt
set    d.TypeRank = dt.Rank
where  d.Type = dt.DeviceTypeID;

## We want to use data from HSRP and VRRP devices only as a
## last resort.
update currentDeviceList
set    TypeRank = 0
where   Type in ('HSRP','VRRP','GLBP');

alter table currentDeviceList add index (DeviceID);

## The first section creates a temporary table that contains a list
## of all known IP addresses on the network.  This table will be 
## populated from a large set of collected data and is the basis for
## network discovery.
##
drop temporary table if exists newDeviceList;

create temporary table newDeviceList (
	IPAddress	varchar(39) not null,
	InetAddr	decimal(39,0) not null,
	DeviceID	bigint,
	IPDeviceID	bigint,
	Type		varchar(32),
	TypeProbability	int,
	Vendor		varchar(50),
	FirstOccurrence	bigint,
	Source		varchar(32),
	ifIndex		int,
	ifName		varchar(128),
	ifType		varchar(32),
	snmpEngineID	char(100),
	Included	tinyint default 0,
	HasIfAddr	tinyint default 0,
	HasIPIntf	tinyint default 0,
	UserMgmtIP	varchar(39),
	AltSNMPIP	varchar(39),
	OrigSNMPIP	varchar(39),
	SysMgmtIP	varchar(39),
	VirtualNetworkID bigint default null,
	constraint pkNewDeviceList primary key ( InetAddr, VirtualNetworkID )
) ENGINE=InnoDB;

alter table newDeviceList
	add index(IPAddress, Type),
	add index(InetAddr),
	add index(DeviceID),
	add index(VirtualNetworkID);

## Commenting out the following fix for NETMRI-18487 as it was causing AUGUSTA2-23.
## There is a clone for NETMRI-18487 - NETMRI-23063 for solution that will work on both NetMRI and NI platforms
# insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, Included, VirtualNetworkID)
# select range_start, range_start_numeric, null, 'Router', 'Seed', 2, virtual_network_id
# from   ${ConfigDB}.discovery_settings
# where  range_type = 'SEED';

##
## Add in any known IP's collected from the ipAddrTable.  If
## NetMRI has collected interface status data for a device 
## then exclude an IP addresses on administratively down 
## interfaces.
##
drop temporary table if exists ifAddrList;

create temporary table ifAddrList as
select a.DeviceID,
       a.ifIndex,
       a.ifIPNumeric as IPAddress,
       a.ifNetMaskNumeric as NetMask,
       a.ifIPDotted as IPAddressDotted,
       i.ifName,
       i.ifType,
       v.VirtualNetworkID
from ${ReportDB}.ifAddr a
join ${ReportDB}.ifConfig i on (a.InterfaceID = i.InterfaceID)
join ${ReportDB}.VirtualNetworkMember v on (i.VirtualNetworkMemberID = v.VirtualNetworkMemberID)
where v.VirtualNetworkID!= 0;

alter table ifAddrList
	modify IPAddress decimal(39,0),
	add index (DeviceID,ifIndex),
	add index (IPAddress,ifIndex);

## Remove interfaces that belong to NetMRI VMs.
## They belong to different VNs but actually gathered as they belong to the same VN
## So impossible to use them during mgmt interface calculation
delete a from ifAddrList a, ${ReportDB}.Device d
where  a.DeviceID = d.DeviceID
and    d.DeviceType = 'NetMRI';

## Remove any admin down interfaces.  But instead of just
## removing them with the following delete statement, we
## need to remove admin down interfaces that might be
## reflected in HSRP ifAddr tables as well and just throwing
## HSRP away probably isn't desirable.  So get a list of
## addresses and ifIndexes on admin down interfaces and
## delete based on that criteria.

#delete a from ifAddrList a, ${NetMRIDB}.ifStatus s
#where  a.DeviceID = s.DeviceID
#and    a.ifIndex = s.ifIndex
#and    AdminStatus != 'up';

drop temporary table if exists adminDownIPs;

create temporary table adminDownIPs as
select a.ifIndex, a.IPAddress, a.DeviceID
from   ifAddrList a, ifStatus s
where  a.DeviceID = s.DeviceID
and    a.ifIndex = s.ifIndex
and    AdminStatus != 'up';

alter table adminDownIPs add index(IPAddress,ifIndex);

delete a from ifAddrList a, adminDownIPs d
where  a.IPAddress = d.IPAddress
and    a.ifIndex = d.ifIndex
and    a.DeviceID = d.DeviceID;

drop temporary table if exists adminDownIPs;

## NETMRI-24010
## Workaround a Cisco bug where some loopback ifAddr entries are assigned ifIndex=0
insert ignore into ifAddrList (DeviceID, IPAddress, IPAddressDotted, ifName, ifType, ifIndex, NetMask)
select DeviceID, IPAddress, IPAddressDotted, Name, Type, ifIndex, NetMask
from ${NetMRIDB}.missingIntfs;

update ifAddrList i, ${NetMRIDB}.currentDeviceList d
set i.VirtualNetworkID = d.VirtualNetworkID
where d.DeviceID = i.DeviceID;

delete from ifAddrList where ifName='' OR ifType='';

## Commenting out the following fix for NETMRI-18487 as it was causing AUGUSTA2-23.
## There is a clone for NETMRI-18487 - NETMRI-23063 for solution that will work on both NetMRI and NI platforms
## Currently we only have seed routers in the newDeviceList table; ensure
## that these entries have correct interface attributes to prevent management
## IP address oscillations
#update newDeviceList d, ifAddrList a
#set    d.ifType = a.ifType,
#       d.ifIndex = a.ifIndex
#where  d.InetAddr = a.IPAddress and d.VirtualNetworkID<=>a.VirtualNetworkID
#and    d.ifType is null
#and    a.ifType is not null;

## Add in all the known IP addresses from the ifAddr table.  Note that for
## cases where we have duplicate instances of a device there will be duplicate
## ifAddr sets as well.  The lowest DeviceID will be associated with those
## just as a way to group them together.  The IPDeviceID column will associate
## a given IP address back to it's actual Device instance if it exists.

## The conditional on the device type below prevents HSRP devices that have an
## ifAddr entry from adding in IP addresses from their ifAddr table as HSRP types
## if these are encountered from the select statement before the actual router
## device.  Only put the known HSRP address in as that type.

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Vendor, FirstOccurrence, Source, ifIndex, ifName, ifType, VirtualNetworkID)
select a.IPAddressDotted, a.IPAddress, 
       if(d.Type not in ('HSRP','VRRP','GLBP') or d.InetAddr = a.IPAddress, a.DeviceID, null),
       if(d.Type not in ('HSRP','VRRP','GLBP') or d.InetAddr = a.IPAddress, d.Type, 'unknown'),
       Vendor,
       FirstOccurrence,
       'ifAddr', ifIndex, ifName, ifType, a.VirtualNetworkID
from   currentDeviceList d,
       ifAddrList a
where  d.DeviceID = a.DeviceID and
       d.Type not like "SDN%"
order by d.TypeRank desc, FirstOccurrence asc, ifIndex asc;

##
## Now add in anything from the Device table itself that doesn't show up in
## the ifAddr table.
##

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, FirstOccurrence, Source, VirtualNetworkID)
select IPAddress, InetAddr, DeviceID, Type, FirstOccurrence, 'Device', VirtualNetworkID
from   currentDeviceList;

##
## Add in NetMRI IPAddress so that it will always be included in collection
##
insert ignore into newDeviceList (VirtualNetworkID, IPAddress, InetAddr, DeviceID, Type, Source)
select @netmriVNID, @netmriIP, netmri.inet_pton(@netmriIP), null, 'NetMRI', 'NetMRI'
from dual
where @netmriIP is not null and @netmriIP != '';

##
## Add in known NIOS grid members
## 
## AUGUSTA-1474 :  only add the address of the grid member that has "Online" status 
##
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select GridMemberIPDotted, GridMemberIPNumeric, null, 'NIOS', 'NIOS', VirtualNetworkID 
from   ${ReportDB}.GridMemberStatus join currentDeviceList using (DeviceID)
where  GridMemberStatus = 'Online' and GridMemberTimestamp > now() - interval 1 day;

update newDeviceList n, ${ReportDB}.GridMemberStatus g
set    n.Type = 'NIOS'
where  n.IPAddress = g.GridMemberIPDotted
and    n.Type = 'unknown';

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select grid_master, netmri.inet_pton(grid_master), null, 'NIOS', 'NIOS', virtual_network_id
from   ${ConfigDB}.ipam_sync_configs
where  netmri.inet_pton(grid_master) is not null
and    netmri.inet_pton(grid_master) != ''
and    sync_sched_ind = 1;

update newDeviceList n, ${ConfigDB}.ipam_sync_configs g
set    n.Type = 'NIOS'
where  n.IPAddress = g.grid_master
and    n.Type = 'unknown'
and    g.sync_sched_ind = 1;

##
## Add in seed routers
##
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, Included, VirtualNetworkID)
select range_start, range_start_numeric, null, 'Router', 'Seed', 2, virtual_network_id
from   ${ConfigDB}.discovery_settings
where  range_type = 'SEED';

## There is a clone for NETMRI-18487 - NETMRI-23063 for solution that will work on both NetMRI and
## NI platforms to avoid AUGUSTA2-23
## In case the device was already existing,
## we just set the Include=2 to avoid device to be delete after by 'Not included on slave' in getExpiredDevices.sql
update newDeviceList n, ${ConfigDB}.discovery_settings s
set n.Included = 2
where s.range_start_numeric <=> n.InetAddr and s.virtual_network_id <=> n.VirtualNetworkID and s.range_type = 'SEED';

##
## Add in managment IPs from virtual devices with known virtual hosts.
## Copy the Type and Type Probability from the host while we are at it.
##
drop temporary table if exists ${NetMRIDB}.tmpAddr;
create temporary table if not exists ${NetMRIDB}.tmpAddr select IPAddressDotted, addr.DeviceID, addr.ifIndex, AdminStatus from ${NetMRIDB}.ifAddr addr join ${NetMRIDB}.ifStatus using (DeviceID, ifIndex);
alter table ${NetMRIDB}.tmpAddr add index(DeviceID), add index(IPAddressDotted);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Source, Type, TypeProbability, FirstOccurrence, VirtualNetworkID)
select c.IPAddress, netmri.inet_pton(c.IPAddress), null, 'Context', d.Type, d.TypeProbability, d.FirstOccurrence, d.VirtualNetworkID
from   ${NetMRIDB}.DeviceContext c join currentDeviceList d on c.DeviceID = d.DeviceID
left join ${NetMRIDB}.Device d_p on c.DeviceID=d_p.ParentDeviceID
left join ${NetMRIDB}.tmpAddr addr on ((c.DeviceID=addr.DeviceID or d_p.DeviceID=addr.DeviceID) and c.IPAddress = addr.IPAddressDotted)
where c.IPAddress != d.IPAddress
and (addr.AdminStatus != 'down' or addr.AdminStatus is null);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Source, Type, TypeProbability, FirstOccurrence, VirtualNetworkID)
select s.SubIPDotted, netmri.inet_pton(s.SubIPDotted), null, 'Subordinate', s.SubType, 75, FirstOccurrence , d.VirtualNetworkID
from   ${NetMRIDB}.DeviceSubordinate s join currentDeviceList d on s.DeviceID = d.DeviceID
where s.SubIPDotted != d.IPAddress;

drop  temporary table if exists ${NetMRIDB}.tmpAddr;
###########################################################################
##
## Add in route destinations and next hops found in the prior 24-hours.
##

drop temporary table if exists tmpRouteTable;

create temporary table tmpRouteTable as
select dr.RouteNextHopIPDotted, dr.RouteNextHopIPNumeric, dr.RouteSubnetIPDotted, dr.RouteSubnetIPNumeric, dr.RouteNetMaskDotted, vm.VirtualNetworkID
from   ${ReportDB}.DeviceRoute as dr
join ${ReportDB}.VirtualNetworkMember as vm
on dr.VirtualNetworkMemberID = vm.VirtualNetworkMemberID
where vm.VirtualNetworkID!=0 and RouteTimestamp > now() - interval 1 day;

alter table tmpRouteTable add index(RouteNextHopIPDotted);
alter table tmpRouteTable add index(RouteSubnetIPDotted);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select RouteNextHopIPDotted, RouteNextHopIPNumeric, null, 'Router', 'Route Table', VirtualNetworkID
from   tmpRouteTable
where  RouteNextHopIPDotted not like '0%'
and    RouteNextHopIPDotted not like '255.%'
and    (RouteNextHopIPDotted like '%.%.%.%' or RouteNextHopIPDotted like '%:%')
and    RouteNextHopIPNumeric != 0;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select RouteSubnetIPDotted, RouteSubnetIPNumeric, null, 'Router', 'Route Table', VirtualNetworkID
from   tmpRouteTable
where  (RouteNetMaskDotted = '255.255.255.255' or RouteNetMaskDotted = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
and    RouteNetMaskDotted not like '0%'
and    RouteNetMaskDotted not like '255.%'
and    (RouteNetMaskDotted like '%.%.%.%' or RouteNetMaskDotted like '%:%')
and    RouteNextHopIPNumeric != 0;

update newDeviceList n, tmpRouteTable r
set    n.Type = 'Router'
where  n.IPAddress = r.RouteNextHopIPDotted
and    r.RouteNextHopIPNumeric != 0
and    n.Type = 'unknown';

update newDeviceList n, tmpRouteTable r
set    n.Type = 'Router'
where  n.IPAddress = r.RouteSubnetIPDotted
and    r.RouteNextHopIPNumeric != 0
and    n.Type = 'unknown';

drop temporary table if exists tmpRouteTable;

###########################################################################
##
## Add in HSRP Table members and virtual IP's found in the prior 24-hours.
##
drop temporary table if exists hsrpStatusTable;

create temporary table hsrpStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'HsrpTable'
and    EndTime > now() - interval 1 day;

alter table hsrpStatusTable add index(DeviceID, EndTime);

#
# Exclude Cisco Nexus devices from discovery via HSRP Tables. Cisco
# Nexus devices have a bug where this data is returned by the main
# context for HSRP variables within a VRF.
#
delete h
  from hsrpStatusTable h
left join ${ReportDB}.InfraDevice d using (DeviceID)
 where d.DeviceID is NULL
    or d.DeviceSysDescr like '%NX-OS%'
    or d.DeviceSysDescr is NULL;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select cHsrpGrpVirtualIpAddr, netmri.inet_pton(cHsrpGrpVirtualIpAddr), null, h.Type, 'HSRP Table Virtual', s.VirtualNetworkID
from   ${NetMRIDB}.HsrpTable h,
       hsrpStatusTable s
where  cHsrpGrpVirtualIpAddr not like '0%' and
       cHsrpGrpVirtualIpAddr not like '255.%' and
       h.DeviceID = s.DeviceID AND
       h.EndTime  = s.EndTime;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select cHsrpGrpActiveRouter, netmri.inet_pton(cHsrpGrpActiveRouter), null, 'Router', 'HSRP Table Active', s.VirtualNetworkID
from   ${NetMRIDB}.HsrpTable h,
       hsrpStatusTable s
where  cHsrpGrpActiveRouter not like '0%' and
       cHsrpGrpActiveRouter not like '255.%' and
       h.DeviceID = s.DeviceID AND
       h.EndTime  = s.EndTime;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select cHsrpGrpStandbyRouter, netmri.inet_pton(cHsrpGrpStandbyRouter), null, 'Router', 'HSRP Table Standby', s.VirtualNetworkID
from   ${NetMRIDB}.HsrpTable h,
       hsrpStatusTable s
where  cHsrpGrpStandbyRouter not like '0%' and
       cHsrpGrpStandbyRouter not like '255.%' and
       h.DeviceID = s.DeviceID AND
       h.EndTime  = s.EndTime;

###########################################################################
##
## Add in wireless bsnAPTable entries found in the prior 24-hours.
##
drop temporary table if exists bsnStatusTable;

create temporary table bsnStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'bsnAPTable'
and    EndTime > now() - interval 1 day;

alter table bsnStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select netmri.inet_ntop(bsnApIpAddress), bsnApIpAddress, null, 'Wireless AP', 'Wireless Controller', s.VirtualNetworkID
from   ${NetMRIDB}.bsnAPTable a,
      bsnStatusTable s
where  bsnApIpAddress > 0
and    bsnApIpAddress < 4294967296
and    a.DeviceID = s.DeviceID
and    a.EndTime  = s.EndTime;

drop temporary table if exists bsnStatusTable;

###########################################################################
## Add LWAPs

drop temporary table if exists tmpLWAPDevices;

create temporary table tmpLWAPDevices
select ws.SubIPDotted as IPAddress , ws.SubIPNumeric as InetAddr, NULL as DeviceID, "LWAP" as Type, d.Vendor as Vendor, "WirelessController" as Source, d.VirtualNetworkID as VirtualNetworkID
from ${ReportDB}.WirelessSubordinant ws
join newDeviceList d on d.DeviceID = ws.DeviceID
where 1=2;

insert into tmpLWAPDevices(IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select ws.SubIPDotted, ws.SubIPNumeric, NULL, "LWAP", d.Vendor, "WirelessController", d.VirtualNetworkID
from ${ReportDB}.WirelessSubordinant ws
join newDeviceList d on d.DeviceID = ws.DeviceID
where ws.SubModel like 'AIR-LAP%' or ws.SubModel like 'C9120%' or ws.SubModel like 'AIR-AP%' or ws.SubModel like 'AIR-CAP%';

insert ignore into newDeviceList(IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID
from tmpLWAPDevices;

update ignore newDeviceList
set
    Type = "LWAP",
    Source = "Wireless Controller",
    Included = 2
where IPAddress in (select IPAddress from tmpLWAPDevices) and Type != 'LWAP';

drop temporary table if exists tmpLWAPDevices;

###########################################################################
## Add Wireless AP w/o SNMP access

drop temporary table if exists tmpWAPDevices;

create temporary table tmpWAPDevices
select ws.SubIPDotted as IPAddress , ws.SubIPNumeric as InetAddr, NULL as DeviceID, "Wireless AP" as Type, d.Vendor as Vendor, "WirelessController" as Source, d.VirtualNetworkID as VirtualNetworkID
from ${ReportDB}.WirelessSubordinant ws
join newDeviceList d on d.DeviceID = ws.DeviceID
where 1=2;

insert into tmpWAPDevices(IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select ws.SubIPDotted, ws.SubIPNumeric, NULL, "Wireless AP", d.Vendor, "WirelessController", d.VirtualNetworkID
from ${ReportDB}.WirelessSubordinant ws
join newDeviceList d on d.DeviceID = ws.DeviceID
where d.Type != 'LWAP' and ws.SubModel not like 'AIR-LAP%' and ws.SubModel not like 'C9120%' and ws.SubModel not like 'AIR-AP%' and ws.SubModel not like 'AIR-CAP%';

insert ignore into newDeviceList(IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID
from tmpWAPDevices;

update ignore newDeviceList
set
    Type = "Wireless AP",
    Source = "Wireless Controller",
    Included = 2
where IPAddress in (select IPAddress from tmpWAPDevices) and Type != 'Wireless AP';

drop temporary table if exists tmpWAPDevices;

###########################################################################
##
## Add in any addresses from the cdpCacheTable found in the prior 24-hours.
##
drop temporary table if exists cdpStatusTable;

create temporary table cdpStatusTable as
select DeviceID, EndTime
from   ${NetMRIDB}.SNMPTableStatus
where  TableName in ('cdpCacheTable', 'ctCDPNeighborTable')
and    EndTime > now() - interval 1 day;

alter table cdpStatusTable add index(DeviceID,EndTime);

drop temporary table if exists cdpCacheCopy;

create temporary table cdpCacheCopy as
select c.DeviceID, cdpCacheAddress, cdpCachePrimaryMgmtAddr, cdpCacheSecondaryMgmtAddr, cdpCacheCapabilities, CAST('CDP' as char(8)) as Source, v.VirtualNetworkID, c.cdpCacheVersion, c.cdpCacheDevicePort, CAST('unknown' as char(32)) as Type, netmri.inet_pton(cdpCacheAddress) as cdpCacheAddressNum, netmri.inet_pton(cdpCachePrimaryMgmtAddr) as cdpCachePrimaryMgmtAddrNum, netmri.inet_pton(cdpCacheSecondaryMgmtAddr) as cdpCacheSecondaryMgmtAddrNum
from  cdpStatusTable s, ${NetMRIDB}.cdpCacheTable c
join ${ReportDB}.ifConfig i on (i.DeviceID = c.DeviceID and c.cdpCacheIfIndex = i.ifIndex)
join ${ReportDB}.VirtualNetworkMember v on (i.VirtualNetworkMemberID = v.VirtualNetworkMemberID)
left join SdnFabricDevice sd on (c.DeviceID = sd.DeviceID)
where  c.DeviceID = s.DeviceID
and    sd.DeviceID is null -- exclude SDN devices
and    c.EndTime = s.EndTime
and    v.VirtualNetworkID!=0;

insert into cdpCacheCopy
select n.DeviceID, n.LLDPNeighborPrimaryIPDotted, n.LLDPNeighborPrimaryIPDotted, n.LLDPNeighborSecondaryIPDotted,
       n.LLDPNeighborCapabilitiesNumeric, 'LLDP', v.VirtualNetworkID, NULL, NULL, 'unknown',
       netmri.inet_pton(n.LLDPNeighborPrimaryIPDotted), netmri.inet_pton(n.LLDPNeighborPrimaryIPDotted), netmri.inet_pton(n.LLDPNeighborSecondaryIPDotted)
from ${ReportDB}.ifLLDPNeighbor n
join ${ReportDB}.ifConfig i on (n.InterfaceID = i.InterfaceID)
join ${ReportDB}.VirtualNetworkMember v on (i.VirtualNetworkMemberID = v.VirtualNetworkMemberID)
left join SdnFabricDevice sd on (n.DeviceID = sd.DeviceID)
where v.VirtualNetworkID!=0
and   sd.DeviceID is null; -- exclude SDN devices

update cdpCacheCopy c
set Type = case when cdpCacheCapabilities = 1 and c.Source = 'CDP' then 'Router'
             when cdpCacheCapabilities = 8 and c.Source = 'LLDP' then 'Router'
             when cdpCacheCapabilities = 8 and c.Source = 'CDP' then 'Switch'
             when cdpCacheCapabilities between 32 and 96 and c.Source = 'LLDP' then 'Switch'
             when cdpCacheCapabilities > 8 and cdpCacheCapabilities < 128 and c.Source = 'CDP' then 'Switch-Router'
             when cdpCacheCapabilities between 40 and 104 and c.Source = 'LLDP' then 'Switch-Router'
             when cdpCacheCapabilities > 128 and c.Source = 'CDP' then 'IP Phone'
             when cdpCacheCapabilities = 4 and c.Source = 'LLDP' then 'IP Phone'
             when cdpCacheCapabilities = 2 and c.Source = 'LLDP' then 'Video QAM'
             when cdpCacheCapabilities = 16 and c.Source = 'LLDP' then 'Wireless Controller'
             else 'unknown'
           end;

alter table cdpCacheCopy add index(cdpCacheAddress);
alter table cdpCacheCopy add index(cdpCacheAddressNum);
alter table cdpCacheCopy add index(cdpCachePrimaryMgmtAddr);
alter table cdpCacheCopy add index(cdpCachePrimaryMgmtAddrNum);
alter table cdpCacheCopy add index(cdpCacheSecondaryMgmtAddr);
alter table cdpCacheCopy add index(cdpCacheSecondaryMgmtAddrNum);

drop temporary table if exists cdpAddrs;
create temporary table cdpAddrs (
	IPAddress	varchar(39) not null,
	InetAddr	decimal(39,0) not null,
	cdpCacheCapabilities int(11) NOT NULL,
	Source		varchar(32),
	VirtualNetworkID bigint default null,
	constraint pkNewDeviceList primary key ( InetAddr, VirtualNetworkID )
);


# Create a list of CDP IP Addresses
insert ignore into cdpAddrs (IPAddress, InetAddr, cdpCacheCapabilities, Source, VirtualNetworkID)
select cdpCacheAddress, cdpCacheAddressNum, cdpCacheCapabilities, Source, VirtualNetworkID
from   cdpCacheCopy c
where  (cdpCacheAddress like '%.%.%.%' or cdpCacheAddress like '%:%');

insert ignore into cdpAddrs (IPAddress, InetAddr, cdpCacheCapabilities, Source, VirtualNetworkID)
select cdpCachePrimaryMgmtAddr, cdpCachePrimaryMgmtAddrNum, cdpCacheCapabilities, Source, VirtualNetworkID
from   cdpCacheCopy c
where  (cdpCachePrimaryMgmtAddr like '%.%.%.%' or cdpCachePrimaryMgmtAddr like '%:%');

insert ignore into cdpAddrs (IPAddress, InetAddr, cdpCacheCapabilities, Source, VirtualNetworkID)
select cdpCacheSecondaryMgmtAddr, cdpCacheSecondaryMgmtAddrNum, cdpCacheCapabilities, Source, VirtualNetworkID
from   cdpCacheCopy c
where  (cdpCacheSecondaryMgmtAddr like '%.%.%.%' or cdpCacheSecondaryMgmtAddr like '%:%');

# Strip out CDP IP Addresses for Cisco Nexus on interface mgmt0
delete a
  from cdpAddrs a
  join cdpCacheCopy c on (a.InetAddr=c.cdpCacheAddressNum)
 where c.cdpCacheVersion like '%NX-OS%'
   and c.cdpCacheDevicePort = 'mgmt0';

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select IPAddress, InetAddr, null,
       case when cdpCacheCapabilities = 1 and Source = 'CDP' then 'Router'
            when cdpCacheCapabilities = 8 and Source = 'LLDP' then 'Router'
            when cdpCacheCapabilities = 8 and Source = 'CDP' then 'Switch'
            when cdpCacheCapabilities between 32 and 96 and Source = 'LLDP' then 'Switch'
            when cdpCacheCapabilities > 8 and cdpCacheCapabilities < 128 and Source = 'CDP' then 'Switch-Router'
            when cdpCacheCapabilities between 40 and 104 and Source = 'LLDP' then 'Switch-Router'
            when cdpCacheCapabilities > 128 and Source = 'CDP' then 'IP Phone'
            when cdpCacheCapabilities = 4 and Source = 'LLDP' then 'IP Phone'
            when cdpCacheCapabilities = 2 and Source = 'LLDP' then 'Video QAM'
            when cdpCacheCapabilities = 16 and Source = 'LLDP' then 'Wireless Controller'
            else 'unknown'
       end,
       Source,
       VirtualNetworkID
from   cdpAddrs;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select ctCDPNeighborIP, netmri.inet_pton(ctCDPNeighborIP), null, 'unknown', 'CDP', v.VirtualNetworkID
from   cdpStatusTable s, ${NetMRIDB}.ctCDPNeighborTable c
join ${ReportDB}.ifConfig i on (i.DeviceID = c.DeviceID and c.ifIndex = i.ifIndex)
join ${ReportDB}.VirtualNetworkMember v on (i.VirtualNetworkMemberID = v.VirtualNetworkMemberID)
where  (ctCDPNeighborIP like '%.%.%.%' or ctCDPNeighborIP like '%:%')
and    c.DeviceID = s.DeviceID
and    c.EndTime  = s.EndTime;

update newDeviceList n, cdpCacheCopy c
set n.Type = c.Type
where  n.InetAddr = c.cdpCachePrimaryMgmtAddrNum
and    n.Type = 'unknown' and c.cdpCachePrimaryMgmtAddr != "";

update newDeviceList n, cdpCacheCopy c
set n.Type = c.Type
where  n.InetAddr = c.cdpCacheSecondaryMgmtAddrNum
and    n.Type = 'unknown' and c.cdpCacheSecondaryMgmtAddr != "";

update newDeviceList n, cdpCacheCopy c
set n.Type = c.Type
where  n.InetAddr = c.cdpCacheAddressNum
and    n.Type = 'unknown';

drop temporary table if exists cdpStatusTable;
drop temporary table if exists cdpCacheCopy;


###########################################################################
## Add SDN devices 
select @SdnNetworkMappingPolicy  := value from config.adv_setting_defs a join config.adv_settings on a.id=adv_setting_def_id where name="SdnNetworkMappingPolicy";
select @DefaultSdnVirtualNetwork := value from config.adv_setting_defs a join config.adv_settings on a.id=adv_setting_def_id where name="DefaultSdnVirtualNetwork";

# create table for all SDN devices, there can be duplicates of IP+VN key
drop temporary table if exists tmpSdnDevices;
create temporary table tmpSdnDevices ENGINE=InnoDB
as
select SdnDeviceID, IPAddress, netmri.inet_pton(IPAddress) as InetAddr, DeviceID, 'unknown' as Type, a.Vendor as Vendor, s.sdn_type as Source, 0 as VirtualNetworkID, 0 as ExistingDevice
from SdnFabricDevice a join ${ConfigDB}.sdn_controller_settings s on a.SdnControllerId = s.id 
where 1=2;

ALTER TABLE tmpSdnDevices
  ADD INDEX (SdnDeviceID);

## Meraki
insert ignore into tmpSdnDevices
select a.SdnDeviceID, a.IPAddress, netmri.inet_pton(a.IPAddress) as InetAddr, a.DeviceID, 'unknown' as Type, a.Vendor as Vendor, s.sdn_type as Source, 
  case 
    when @SdnNetworkMappingPolicy = 'DISABLED' then @DefaultSdnVirtualNetwork 
    when @SdnNetworkMappingPolicy in ('AUTO','RULE_BASED') then sn.virtual_network_id 
    else s.virtual_network_id
  end as VirtualNetworkID,
  n.DeviceID is not null as ExistingDevice
from SdnFabricDevice a join ${ConfigDB}.sdn_controller_settings s on a.SdnControllerId = s.id 
left join SdnNetwork sn on locate(concat(sn.sdn_network_key,'/'),SdnDeviceDN) = 1 and a.SdnControllerId = sn.fabric_id
left join newDeviceList n using(DeviceID)
where s.sdn_type in ('Meraki', 'Mist');

## Other
insert ignore into tmpSdnDevices (SdnDeviceID, IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID, ExistingDevice)
select sd.SdnDeviceID, sd.IPAddress, netmri.inet_pton(sd.IPAddress), sd.DeviceID, 'unknown', sd.Vendor, s.sdn_type, s.virtual_network_id, n.DeviceID is not null
from SdnFabricDevice sd
join ${ConfigDB}.sdn_controller_settings s on sd.SdnControllerId = s.id
left join newDeviceList n using(DeviceID)
where s.sdn_type not in ('Meraki', 'Mist');

# create table for unique SDN devices which can exist in newDeviceList without conflicts
drop temporary table if exists uniqueSdnDevices;
create temporary table uniqueSdnDevices like tmpSdnDevices;
alter table uniqueSdnDevices add unique index(InetAddr, VirtualNetworkID);

insert ignore into uniqueSdnDevices
select * from tmpSdnDevices;

update tmpSdnDevices t
left join uniqueSdnDevices u using(SdnDeviceID)
set
    t.Source = 'SDN_DUPLICATE'
where u.SdnDeviceID is null;

update ignore newDeviceList n, uniqueSdnDevices t
set 
    n.IPAddress        = t.IPAddress,
    n.InetAddr         = t.InetAddr,
    n.Type             = t.Type,
    n.Vendor           = t.Vendor,
    n.Source           = t.Source,
    n.VirtualNetworkID = t.VirtualNetworkID
where t.ExistingDevice = 1
and n.DeviceID = t.DeviceID;

# mark SDN devices in newDeviceList as duplicates, discoveryEngine will delete such devices
update newDeviceList n, tmpSdnDevices t
set
    n.Source = 'SDN_DUPLICATE'
where t.ExistingDevice = 1
and   n.DeviceID = t.DeviceID
and   t.Source = 'SDN_DUPLICATE';

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID
from uniqueSdnDevices
where ExistingDevice = 0;

UPDATE newDeviceList n
JOIN SdnFabricDevice a ON n.IPAddress = a.IPAddress
SET n.Type = CASE
    when a.NodeRole = 'controller' then 'SDN Controller'
    when a.NodeRole = 'spine' then 'SDN Element'
    when a.NodeRole = 'leaf' then 'SDN Element'
    when a.NodeRole = 'Meraki Systems Manager' then 'SDN Controller'
    when a.NodeRole like 'Meraki%' then 'SDN Element'
    when a.NodeRole = 'vmanage' then 'SDN Controller'
    when a.NodeRole = 'vsmart' then 'SDN Controller'
    when a.NodeRole = 'vbond' then 'SDN Controller'
    when a.NodeRole = 'vedge' then 'SDN Element'
    when a.NodeRole = 'MIST ap' then 'SDN AP'
    when a.NodeRole like 'MIST%' then 'SDN Element'      
    when a.NodeRole like 'SilverPeak%' then 'SDN Element' 
    when a.NodeRole like 'VeloCloud Gateway' then 'SDN Controller'
    when a.NodeRole like 'VeloCloud%' then 'SDN Element'	
    else 'unknown'
END;

## Add SDN controllers which do not yet have any devices discovered
replace into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Vendor, Source, VirtualNetworkID)
select SdnControllerIP.ip, netmri.inet_pton(SdnControllerIP.ip), DeviceID, 'SDN Controller', a.Vendor, s.sdn_type, virtual_network_id
from ${ConfigDB}.sdn_controller_settings s 
join SdnControllerIP on s.id = SdnControllerIP.controller_id
left join SdnFabricDevice a on a.SdnControllerId = s.id and NodeRole in ('controller','Meraki Systems Manager','vmanage','vsmart','vbond')
where s.on_prem=1 and a.IPAddress is null and s.UnitID = ${UnitID};

# Now insert SDN interfaces
# XXX: NIOS-73088 a.VirtualNetworkID is referenced to VirtualNetworkMember table,
# which is not working for Cisco Meraki, but could work for Cisco ACI since it supports VRF
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Vendor, FirstOccurrence, Source, ifIndex, ifName, ifType, VirtualNetworkID)
select a.IPAddressDotted, a.IPAddress, 
       a.DeviceID,
       d.Type,
       d.Vendor,
       d.FirstOccurrence,
       'ifAddr', ifIndex, ifName, ifType, 
       # only Cisco ACI devices use VirtualNetworkMember for mapping
       if(sd.Source = 'CISCO_APIC', a.VirtualNetworkID, sd.VirtualNetworkID)
from   currentDeviceList d,
       uniqueSdnDevices sd,
       ifAddrList a
where  d.DeviceID = a.DeviceID and
       d.Type like "SDN%" and
       d.DeviceID = sd.DeviceID
order by d.TypeRank desc, FirstOccurrence asc, ifIndex asc;

###########################################################################
##
## Add in any addresses of Avaya IP phones from entptMCIPINUSE OID
## Add in any addresses of Avaya VoIP Gateways from cmgActiveControllerAddress
## Add in any addresses found in VoipCallDevice
##

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source)
select Value, netmri.inet_pton(Value), null, 'Call Server', 'IP Phone'
from   ${NetMRIDB}.DeviceProperty
where  PropertyName in (
	'endptMCIPINUSE',
	'cmgActiveControllerAddress'
)
and    Value like '%.%.%.%'
and    Timestamp > now() - interval 1 day;

drop temporary table if exists voipStatusTable;

create temporary table voipStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'VoipCallDevice'
and    EndTime > now() - interval 1 day;

alter table voipStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select IPAddress, netmri.inet_pton(IPAddress), null,
       case when DeviceClass = 'Phone' then 'IP Phone'
            when DeviceClass = 'Gateway' then 'VoIP Gateway'
            else DeviceClass
       end,
       'Call Server',
       VirtualNetworkID
from   ${NetMRIDB}.VoipCallDevice d,
       voipStatusTable s
where  d.DeviceID = s.DeviceID
and    d.EndTime = s.EndTime
and    IPAddress like '%.%.%.%';

drop temporary table if exists voipStatusTable;

###########################################################################
##
## Add in any addresses from the Netscreen nsVpnMonTable and nsAddrTable
## found in the prior 24-hours.
##
drop temporary table if exists vpnStatusTable;

create temporary table vpnStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'nsVpnMonTable'
and    EndTime > now() - interval 1 day;

alter table vpnStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select nsVpnMonRmtGwIp, netmri.inet_pton(nsVpnMonRmtGwIp), null, 'Firewall', 'VPN Table', s.VirtualNetworkID
from   ${NetMRIDB}.nsVpnMonTable v,
       vpnStatusTable s
where  v.DeviceID = s.DeviceID
and    v.EndTime = s.EndTime
and    nsVpnMonRmtGwIp not like '0.0.0.0'
and    nsVpnMonRmtGwIp not like '127.%'
and    nsVpnMonRmtGwIp not like '255.%';

drop temporary table if exists vpnStatusTable;

drop temporary table if exists nsAddrStatusTable;

create temporary table nsAddrStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'nsAddrTable'
and    EndTime > now() - interval 1 day;

alter table nsAddrStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select nsAddrIpOrDomain, netmri.inet_pton(nsAddrIpOrDomain), null, 'unknown', 'VPN Table', s.VirtualNetworkID
from   ${NetMRIDB}.nsAddrTable a,
       nsAddrStatusTable s
where  a.DeviceID = s.DeviceID
and    a.EndTime = s.EndTime
and    nsAddrIpOrDomain not like '0.0.0.0'
and    nsAddrIpOrDomain not like '127.%'
and    nsAddrIpOrDomain not like '255.%'
and    nsAddrNetmask = '255.255.255.255'
and    nsAddrIpOrDomain regexp '^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$';

drop temporary table if exists nsAddrStatusTable;

###########################################################################
##
## Add in wireless awcTpFdbTable entries found in the prior 24-hours.
##
drop temporary table if exists awcStatusTable;

create temporary table awcStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'awcTpFdbTable'
and    EndTime > now() - interval 1 day;

alter table awcStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select awcTpFdbIPv4Addr, netmri.inet_pton(awcTpFdbIPv4Addr), null, 'unknown', 'Wireless AP', s.VirtualNetworkID
from   ${NetMRIDB}.awcTpFdbTable a,
      awcStatusTable s
where  awcTpFdbIPv4Addr != '255.255.255.255'
and    awcTpFdbIPv4Addr != '0.0.0.0'
and    awcTpFdbAddress != 'FF:FF:FF:FF:FF:FF'
and    awcTpFdbAddress != '00:00:00:00:00:00'
and    a.DeviceID = s.DeviceID
and    a.EndTime  = s.EndTime;

drop temporary table if exists awcStatusTable;

###########################################################################
##
## Add in wireless bsnMobileStationTable entries
##
drop temporary table if exists bsnStatusTable;

create temporary table bsnStatusTable as
select s.DeviceID, s.EndTime, d.VirtualNetworkID
from   ${NetMRIDB}.SNMPTableStatus s
join currentDeviceList d on s.DeviceID = d.DeviceID
where  TableName = 'bsnMobileStationTable'
and    EndTime > now() - interval 1 day;

alter table bsnStatusTable add index(DeviceID,EndTime);

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select netmri.inet_ntop(bsnMobileStationIpAddress), bsnMobileStationIpAddress, null, 'unknown', 'Wireless Controller', s.VirtualNetworkID
from   ${NetMRIDB}.bsnMobileStationTable a,
     bsnStatusTable s
where  bsnMobileStationIpAddress > 0
and    bsnMobileStationIpAddress < 4294967296
and    a.DeviceID = s.DeviceID
and    a.EndTime  = s.EndTime;

 drop temporary table if exists bsnStatusTable;

###########################################################################
##
## Add in ARP table entries.
##

# First figure out which ARP entries point to HSRP addresses.  Only 
# get IP's with one MAC associated to them.  Otherwise something 
# else on the network is happening such as a honeypot causing issues 
# and would end up misclassifying devices.  
#
# Note: The following set of inserts using the ARP table used to be
# a single statement, but having knowledge of which IP's might be
# an HSRP address is needed later on, so the temporary table is built
# with those addresses.

# create temporary table to join a VirtualNetworkID
drop table if exists tmpArp;

create temporary table tmpArp (
        IfArpID                 BIGINT UNSIGNED not null,
        InterfaceID             BIGINT UNSIGNED,
        IPAddrDotted            varchar(39),
        IPAddrNumeric           decimal(39),
        PhysicalAddr            char(32),
        ArpTimestamp            datetime,
        VirtualNetworkID        BIGINT UNSIGNED,
        constraint primary key (IfArpID)
);

insert ignore into tmpArp
select a.IfArpID, a.InterfaceID, a.IPAddrDotted, a.IPAddrNumeric, a.PhysicalAddr, a.ArpTimestamp, v.VirtualNetworkID
from ${ReportDB}.ifArp a
join ${ReportDB}.Device d on d.DeviceID = a.DeviceID
join ${ReportDB}.ifConfig c on a.InterfaceID = c.InterfaceID
join ${ReportDB}.VirtualNetworkMember v on c.VirtualNetworkMemberID = v.VirtualNetworkMemberID
where v.VirtualNetworkID!=0 and d.DeviceType != 'NetMRI';

## insert ARP of current NetMRI only, we dont need ARPs for others, they be gathered in Collector anyway
insert ignore into tmpArp
select a.IfArpID, a.InterfaceID, a.IPAddrDotted, a.IPAddrNumeric, a.PhysicalAddr, a.ArpTimestamp, i.virtual_network_id
from ${ReportDB}.ifArp a
join ${ReportDB}.ifConfig c on a.InterfaceID = c.InterfaceID
join ${ConfigDB}.scan_interfaces i on c.ifName = i.if_dev
where a.DeviceID = @netmriDeviceID;

drop temporary table if exists hsrpAddrs;

create temporary table hsrpAddrs (
	InetAddr	decimal(39,0),
	Type		char(4),
	VirtualNetworkID BIGINT UNSIGNED,
	constraint primary key (InetAddr)
);

insert ignore into hsrpAddrs
select IPAddrNumeric, 'HSRP', VirtualNetworkID
from  tmpArp
where  ArpTimestamp > now() - interval 1 day
and    PhysicalAddr like '00:00:0C:07:AC%'
group by IPAddrNumeric
having count(distinct IPAddrNumeric, PhysicalAddr) = 1;

insert ignore into hsrpAddrs
select IPAddrNumeric, 'VRRP', VirtualNetworkID
from   tmpArp
where  ArpTimestamp > now() - interval 1 day
and    PhysicalAddr like '00:00:5E:00:01%'
group by IPAddrNumeric
having count(distinct IPAddrNumeric, PhysicalAddr) = 1;

insert ignore into hsrpAddrs
select IPAddrNumeric, 'GLBP', VirtualNetworkID
from  tmpArp
where  ArpTimestamp > now() - interval 1 day
and    PhysicalAddr like '00:07:B4%'
group by IPAddrNumeric
having count(distinct IPAddrNumeric, PhysicalAddr) = 1;
# Now add in the HSRP addresses and other ARP entries.

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select netmri.inet_ntop(InetAddr), InetAddr, null, Type, 'ARP Table', VirtualNetworkID
from   hsrpAddrs;

drop temporary table if exists arpEntry;

create temporary table arpEntry as
select IPAddrDotted, IPAddrNumeric, PhysicalAddr, substr(PhysicalAddr,1,8) as OUI, VirtualNetworkID 
from   tmpArp
where  ArpTimestamp > now() - interval 1 day
and    PhysicalAddr != 'FF:FF:FF:FF:FF:FF'
and    PhysicalAddr != '00:00:00:00:00:00'
and    PhysicalAddr not like '00:00:0C:07:AC%'
and    PhysicalAddr not like '00:00:5E:00:01%'
and    PhysicalAddr not like '00:07:B4%'
;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select IPAddrDotted, IPAddrNumeric, null, 'unknown', 'ARP Table', VirtualNetworkID
from   arpEntry;

## Set Device.Vendor based on MAC OUI of vendors NetMRI supports
## if Vendor isn't already set so the credential guesser gives them
## priority.

alter table arpEntry add Vendor varchar(255);
alter table arpEntry add index(OUI);

update arpEntry a, netmri.IEEE_OUI_Assignments o
set    a.Vendor = o.Vendor
where  a.OUI = o.OUI
and    Priority = 1;

update ${NetMRIDB}.Device d, arpEntry a
set    d.Vendor = a.Vendor
where  ${testOnly} = 0
and    d.Vendor is null
and    d.IPAddress = a.IPAddrDotted;

drop temporary table if exists arpEntry;
drop table if exists tmpArp;

###########################################################################
##
## Process the data from the DiscoveryDataQueue table.  If a MAC is
## present use it to help seed a specific vendor if known.  We keep 
## data in DiscoveryDataQueue for two passes.  The first to just create
## any devices.  Then the second to set the vendor based on MAC where
## it's not yet known.
##

update ${NetMRIDB}.DiscoveryDataQueue set Status = 'vendor' where Status is not null;
update ${NetMRIDB}.DiscoveryDataQueue set Status = 'discovery' where Status is null;

drop temporary table if exists tmpDataQueue;

create temporary table tmpDataQueue as
select IPAddress, netmri.inet_pton(IPAddress) as IPAddressNumeric, Source, substr(MacAddress,1,8) as OUI
from   ${NetMRIDB}.DiscoveryDataQueue
where  Status is not null
;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source)
select IPAddress, IPAddressNumeric, null, 'unknown', Source
from   tmpDataQueue
;

alter table tmpDataQueue add Vendor varchar(255);
alter table tmpDataQueue add index(OUI);

update tmpDataQueue q, netmri.IEEE_OUI_Assignments o
set    q.Vendor = o.Vendor
where  q.OUI = o.OUI
and    Priority = 1;

update ${NetMRIDB}.Device d, tmpDataQueue q
set    d.Vendor = q.Vendor
where  ${testOnly} = 0
and    d.Vendor is null
and    d.IPAddress = q.IPAddress;

drop temporary table if exists tmpDataQueue;
delete from ${NetMRIDB}.DiscoveryDataQueue where Status = 'vendor';

###########################################################################
##
## Add in /32 CIDR blocks.
##
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select range_start, range_start_numeric, null, 'unknown', range_type, virtual_network_id
from   ${ConfigDB}.discovery_settings
where  discovery_status = 'INCLUDE'
and    ((range_type = 'CIDR' and range_mask in (32,128)) OR (range_type = 'STATIC'));

###########################################################################
##
## Add in IP addresses discovered during a subnet ping sweep.
##
update ${NetMRIDB}.SubnetSweepDataQueue set processFlag = 1;

insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select IPAddress, netmri.inet_pton(IPAddress), null, 'unknown', 'Subnet Scan', VirtualNetworkID
from   ${NetMRIDB}.SubnetSweepDataQueue
where  processFlag = 1;

delete from ${NetMRIDB}.SubnetSweepDataQueue where processFlag = 1;

###########################################################################
##
## Add in IPs from device_certificates, default Type to the likely type,
## based on certificate type where we can make a safe assumtion.
##
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source)
select ip_address_dotted, ip_address_numeric, null, 
  case certificate_type 
    when 'OPSEC' then 'Security Manager'
    else 'unknown' 
  end as Type, 
  'Device Certificate'
from   ${ConfigDB}.device_certificates;

###########################################################################
##
## Set the device type of any IP's in the device list that are found to be 
## HSRP virtual IP's an HSRP type so they aren't considered as managment IP's
## later on.
##

drop temporary table if exists hsrpCopy;

create temporary table hsrpCopy as
select h.DeviceID, netmri.inet_pton(cHsrpGrpVirtualIpAddr) as cHsrpGrpVirtualIpAddr, Type
from   HsrpTable h, hsrpStatusTable s
where  h.DeviceID = s.DeviceID
and    h.EndTime = s.EndTime;

alter table hsrpCopy add index (cHsrpGrpVirtualIpAddr);

update newDeviceList d, hsrpCopy h
set    d.Type = h.Type
where  InetAddr = cHsrpGrpVirtualIpAddr
and    d.Type != h.Type;

# I feel like this is a hack, but if NetMRI hasn't collected an HSRPTable
# that contains a virtual IP (older IOS devices or because only one member
# of a group is configured and is on the same interface as the desired
# management IP - a chicken and egg problem), then NetMRI will set the
# HSRP address to a router once it gets into the management IP, causing
# NetMRI then to pick the HSRP address as the management IP (if smallest)
# and causing the real device to be deleted.  Then the cycle continues.  
# This change of device type from router to hsrp happens above in the
# insert into newDeviceList.

update newDeviceList d, hsrpAddrs h
set    d.Type = h.Type
where  d.InetAddr = h.InetAddr
and    d.Type in ('Router','Switch-Router','unknown');

drop temporary table if exists hsrpStatusTable;
drop temporary table if exists hsrpCopy;

###########################################################################
##
## Assign the snmpEngineID to each IP.  For any IP address that was found
## to match the snmpEngineID on an existing known device and that IP address
## isn't assigned to a device then it is probably an IP alias so update the
## ifIndex and ifType to mark it as such.
## 

update newDeviceList d, ${NetMRIDB}.IpAddressMap a
set    d.snmpEngineID = a.snmpEngineID
where  d.InetAddr = a.IpAddress and d.VirtualNetworkID = a.VirtualNetworkID;


drop temporary table if exists deviceEngineMap;

# Get a list of devices that have ifAddr tables.  An IP alias won't be
# in this table so we can then look for the same snmpEngineID assigned
# to these that don't have an ifIndex and assume they are IP aliases.
# To handle IP address swings, only consider it an alias if the source
# of the IP data isn't known or ARP table.  Other sources would be an
# indication that it should show up in an ipAddrTable.

create temporary table deviceEngineMap as
select distinct DeviceID, Type, snmpEngineID
from   newDeviceList
where  DeviceID is not null
and    snmpEngineID is not null
and    ifIndex is not null;

alter table deviceEngineMap add index(snmpEngineID);

update newDeviceList d, deviceEngineMap e
set    d.DeviceID = e.DeviceID,
       d.Type = e.Type,
       d.ifIndex = 10000,
       d.ifType = 'alias'
where  d.snmpEngineID = e.snmpEngineID
and    (d.DeviceID != e.DeviceID or d.DeviceID is null)
and    d.ifIndex is null
and    (d.Source is null OR d.Source in ('ARP Table','CIDR Table','Device','Subnet Scan'));

##
## Kill any IpAddressMap entry that appears to be an alias but
## probably isn't because it is showing up in something like CDP
## which would indicate that it now would be in an ipAddrTable.
## I love this special hack for Cisco.  This should pretty much
## match the same boolean logic as the previous query.
##
# almost sure this is not needed anymore, todo: remove later
# delete a from ${NetMRIDB}.IpAddressMap a, newDeviceList d, deviceEngineMap e
# where  ${testOnly} = 0
# and    a.IpAddress = d.InetAddr
# and    a.VirtualNetworkID = d.VirtualNetworkID
# and    d.snmpEngineID = e.snmpEngineID
# and    (d.DeviceID != e.DeviceID or d.DeviceID is null)
# and    d.ifIndex is null;

drop temporary table if exists deviceEngineMap;

###########################################################################
##
## This will set the IPDeviceID column to the DeviceID of the device that
## actually has the given IP address as its Device.IPAddress value.  This
## is needed in case the DeviceID column of the given IP address is 
## associated to another DeviceID because of duplicate instances of a device
## in the database.
##

update newDeviceList d, currentDeviceList c
set    d.IPDeviceID = c.DeviceID,
       d.TypeProbability = c.TypeProbability,
       # keep the suggested device type if current type is unknown or suggested type related to SDN 
       d.Type = IF( (c.Type = 'unknown' or (d.Type in ("SDN Element","SDN AP","SDN Controller")) ), d.Type, c.Type)
where  d.InetAddr = c.InetAddr and d.VirtualNetworkID = c.VirtualNetworkID;

## For any device that was added from a collect ifAddr table on an HSRP
## device the DeviceID will be null, so set it to IPDeviceID so there isn't
## an attempt to create it as a new device.

update newDeviceList
set    DeviceID = IPDeviceID
where  DeviceID is null
and    IPDeviceID is not null;


###########################################################################
##
## For each device mark if it has a collected ifAddr table.  We don't
## want to delete a device with an ifAddr table because it is no longer
## the primary but the primary doesn't yet have it otherwise the other
## IP's will end up getting rediscovered again until the primary gets
## an ifAddr table.  
##

update newDeviceList d, ifAddrList a
set    d.HasIfAddr = 1
where  d.IPDeviceID = a.DeviceID;

###########################################################################
##
## For each device mark if it IPAddress present in the collected ifAddr table.
## Used for de-duplication by SNMPEngineID
##

update newDeviceList d, ${ReportDB}.ifAddr i
set   d.HasIPIntf = 1
where d.IPDeviceID = i.DeviceID and d.InetAddr = i.ifIPNumeric;

###########################################################################
##
## If all aliases are discovered before the mgmt IP, then the ifIndex and
## ifName are still going to be null at this point.  So set them accordingly
## so the discovery engine knows that the interface configuration is known
## from them once it has actually collected the ifConfig data for the device.
##
update newDeviceList d, ifConfig i
set    d.ifIndex = 10000,
       d.ifType = 'alias'
where  d.DeviceID = i.DeviceID
and    d.ifIndex is null
and    d.HasIfAddr = 1;


###########################################################################
##
## For Alcatel 7705 and 7750 devices, the management IPs could be managed
## separately. The management IP is stored in another mib variable.
##
insert ignore into newDeviceList (DeviceID, IPAddress, IPDeviceID, InetAddr, ifIndex, ifType, Source, VirtualNetworkID)
select d.DeviceID, Value, null, netmri.inet_pton(Value), if(PropertyName = 'sbiActiveIpAddr', 1001, 1002), 'softwareLoopback', 'Device', d.VirtualNetworkID
from ${NetMRIDB}.DeviceProperty dp, currentDeviceList d
where dp.PropertyName in ('sbiActiveIpAddr', 'sbiStandbyIpAddr') and dp.DeviceID = d.DeviceID;

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set d.ifIndex = if(PropertyName = 'sbiActiveIpAddr', 1001, 1002), d.ifType = 'softwareLoopback'
where d.DeviceID = dp.DeviceID
and dp.PropertyName in ('sbiActiveIpAddr','sbiStandbyIpAddr')
and d.HasIfAddr = 1 and d.ifIndex is null;

###########################################################################
##
## For Citrix the managment IP address is found at sysIpAddress via SNMP,
## and we cannot use the ifTable.  NetMRI::SNMP::IPAddress::Citrix invents
## ifEntrys in the ifTable which are not present in the SNMP from the device
## based on the ifAddr field in the nsIpAddrTable.  Here we find the faux
## ifEntry which matches the IP address pointed to from sysIpAddress and 
## mark it as softwareLoopback so that it will be favored over the other
## faux entries in the ifTable created by NetMRI::SNMP::IPAddress::Citrix
## when picking the managment address.

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set d.ifType = 'softwareLoopback'
where d.DeviceID = dp.DeviceID
and dp.PropertyName = 'sysIpAddress'
and dp.Value = d.IPAddress;

####################################################################################
##
##For Nortel VSP 9012, managment IP address is found at rcSysVirtualIpAddr via SNMP.
##
insert ignore into newDeviceList (DeviceID, IPAddress, IPDeviceID, InetAddr, ifIndex, ifType, Source, VirtualNetworkID)
select d.DeviceID, Value, null, netmri.inet_pton(Value), if(PropertyName = 'rcSysVirtualIpAddr', 1001, 1002), 'softwareLoopback', 'Device', d.VirtualNetworkID
from ${NetMRIDB}.DeviceProperty dp, currentDeviceList d
where dp.PropertyName in ('rcSysVirtualIpAddr') and dp.DeviceID = d.DeviceID;

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set d.ifType = 'softwareLoopback', d.ifIndex = 1001
where d.DeviceID = dp.DeviceID
and dp.PropertyName = 'rcSysVirtualIpAddr'
and dp.Value = d.IPAddress
and d.HasIfAddr = 1 and d.ifIndex is null;

###########################################################################
##
## NETMRI-16366
## A trick to make sure the addresses in the ifAddr table will be preferred
## over the ILO interface addresses for Windows servers with ILO interfaces
##
## If only the ILO interface is present, then use the ILO interface address
## as the management IP address.
##

update newDeviceList d, DeviceProperty dp
set d.ifType = 'softwareLoopback'
where dp.PropertyName = 'cpqSm2NicIpAddress'
and d.DeviceID = dp.DeviceID
and d.Source = 'ifAddr'
and d.ifType is null
and d.ifIndex is not null;

update newDeviceList d, DeviceProperty dp
set d.ifType = 'ilo', ifIndex = 10000
where dp.PropertyName = 'cpqSm2NicIpAddress'
and d.DeviceID = dp.DeviceID
and d.IPAddress = dp.Value
and d.ifIndex is null;

##
## Add in userIP from a Discover Now
##
insert ignore into newDeviceList (IPAddress, InetAddr, DeviceID, Type, Source, VirtualNetworkID)
select '${userIP}', netmri.inet_pton('${userIP}'), null, 'unknown', '${userIPSource}', '${vnid}'
from dual
where '${userIP}' != '';

###########################################################################
##
## Now get rid of any address that isn't included or ignored.
## Ignored IP's can get created.  They just won't get managed.
##
drop temporary table if exists CidrRanges;

create temporary table CidrRanges (
    NumAddr	decimal(39,0),
    LastAddr	decimal(39,0),
    DotAddr	varchar(39),
    BaseAddr	varchar(39),
    Included	int, -- 0 exclude, 1 ignore, 2 include
    NumMask	int,
    VirtualNetworkID bigint,
    INDEX `VirtualNetworkID` (`VirtualNetworkID`)
);

alter table newDeviceList add column NumMask int;

insert	into CidrRanges
select	NumAddr, (NumAddr + BlockSize - 1) as LastAddr, DotAddr, 
	'%' as BaseAddr, 
	if(DiscoveryMode='INCLUDE',2,if(DiscoveryMode='IGNORE',1,0)), NumMask, VirtualNetworkID
from	CIDR
where   VirtualNetworkID is not null and VirtualNetworkID!=0 and NumMask not in(32,128);

update CidrRanges
set    BaseAddr = concat(substring_index(DotAddr,'.',if(NumMask>=24 and NumMask<32,3,if(NumMask>=16,2,1))),'.%')
where  NumMask between 8 and 31;

create index CR_Index1 on CidrRanges (VirtualNetworkID, NumAddr, LastAddr);

drop temporary table if exists CidrStatics;

create temporary table CidrStatics (
    NumAddr	decimal(39,0),
    LastAddr	decimal(39,0),
    DotAddr	varchar(39),
    BaseAddr	varchar(39),
    Included	int, -- 0 exclude, 1 ignore, 2 include
    NumMask	int,
    VirtualNetworkID bigint,
    INDEX `VirtualNetworkID` (`VirtualNetworkID`)
);

insert	into CidrStatics
select	NumAddr, (NumAddr + BlockSize - 1) as LastAddr, DotAddr, 
	netmri.inet_ntop(NumAddr) as BaseAddr, 
	if(DiscoveryMode='INCLUDE',2,if(DiscoveryMode='IGNORE',1,0)), NumMask, VirtualNetworkID
from	CIDR
where   VirtualNetworkID is not null and VirtualNetworkID!=0 and NumMask in(32,128);

create index CS_Index1 on CidrStatics (VirtualNetworkID, NumAddr);


-- Build summary resultset from 2 tables: CidrRanges and CidrRanges
call updateNewDeviceListWithCIDR();

update	newDeviceList 
set	Included = 2
where	((IPAddress = @netmriIP and VirtualNetworkID = @netmriVNID) or DeviceID = @netmriDeviceID)
	and   @netmriIP is not null and @netmriIP != '';

## SDN Fabric devices and LWAPs are included automatically whether they fit into discovery ranges or not
update newDeviceList set Included = 2
where Type in ('SDN Controller', 'SDN Element', 'SDN AP', 'LWAP');

##
## Update DiscoveryStatus value for new devices
##
update	${NetMRIDB}.Device d, newDeviceList n
set	d.DiscoveryStatus = if(Included = 2, 'INCLUDE',if(Included = 1, 'IGNORE', 'EXCLUDE'))
where	d.IPAddress = n.IPAddress and d.VirtualNetworkID = n.VirtualNetworkID;

## Remove any system loopback addresses

delete from newDeviceList
where  Included = 0 or InetAddr = 0;

###########################################################################
##
## Add in user-specified management addresses and collector determined
## alternate IPs because of reachability problems.
##

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set    d.UserMgmtIP = dp.Value
where  d.DeviceID = dp.DeviceID
and    dp.PropertyName = 'ManagementIP'
and    dp.Source = 'User';

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set    d.SysMgmtIP = dp.Value
where  d.DeviceID = dp.DeviceID
and    dp.PropertyName = 'sysMgmtAddress';

update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set    d.AltSNMPIP = dp.Value,
       d.OrigSNMPIP = dp.PropertyIndex
where  d.DeviceID = dp.DeviceID
and    dp.PropertyName = 'Alternate IP';

## concatenate alt and orig addresses in form IP|VNID it will split after
update newDeviceList d, ${NetMRIDB}.DeviceProperty dp
set    d.AltSNMPIP = CONCAT(d.AltSNMPIP, '|', dp.Value),
       d.OrigSNMPIP = CONCAT(d.OrigSNMPIP, '|', dp.PropertyIndex)
where  d.DeviceID = dp.DeviceID
and    dp.PropertyName = 'Alternate VN';

update newDeviceList d, ${NetMRIDB}.SdnFabricDevice afd
set    d.UserMgmtIP = afd.IPAddress
where  d.DeviceID = afd.DeviceID
and    afd.NodeRole != 'controller' and afd.NodeRole != 'Meraki Systems Manager';

##
## If we now have some indication that an unknown is something else, set it here
##
update ${NetMRIDB}.Device d, newDeviceList n
set    d.Type = n.Type,
       d.TypeProbability = 20,
       d.LastTimeStamp = now(), d.LastSource = 'Type Probability - gDL'
where  d.IPAddress = n.IPAddress
and    d.Type = 'unknown'
and    n.Type != 'unknown';

##
## For SDN devices it is possible to find stale entries (after SNMP discovery) with different Type in Device table.
##
update ${NetMRIDB}.Device d, newDeviceList n
set    d.Type = n.Type,
       d.TypeProbability = 20,
       d.LastTimeStamp = now(), d.LastSource = 'Type Probability - gDL SDN'
where  d.IPAddress = n.IPAddress
and    d.VirtualNetworkID = n.VirtualNetworkID
and    d.Type not in ('SDN Element','SDN Controller','SDN AP')
and    n.Type in ('SDN Element','SDN Controller','SDN AP');

## populate WirelessSubordinant record with DeviceID
update ${ReportDB}.WirelessSubordinant ws
join newDeviceList n on n.IPAddress = ws.SubIPDotted and n.Type = 'LWAP'
set ws.LWAPDeviceID = n.DeviceID;

## populate SdnFabricDevice record with DeviceID if found
## XXX: for Meraki devices combination of n.VirtualNetworkID and n.IPAddress sometimes is not unique
## hence duplicates will get DeviceID = NULL
DROP TEMPORARY TABLE IF EXISTS tmpSdnDeviceUpdate;
CREATE TEMPORARY TABLE tmpSdnDeviceUpdate (
    SdnDeviceID BIGINT UNSIGNED NOT NULL,
    NewDeviceID BIGINT UNSIGNED,
    PRIMARY KEY (SdnDeviceID)
) ENGINE=InnoDB;

INSERT INTO tmpSdnDeviceUpdate (SdnDeviceID, NewDeviceID)
SELECT
    a.SdnDeviceID,
    IF(ts.Source = 'SDN_DUPLICATE' OR ts.VirtualNetworkID = 0, NULL, n.DeviceID) AS NewDeviceID
FROM ${NetMRIDB}.SdnFabricDevice a
LEFT JOIN tmpSdnDevices ts USING(SdnDeviceID)
LEFT JOIN newDeviceList n
    ON n.IPAddress = ts.IPAddress
    AND n.VirtualNetworkID = ts.VirtualNetworkID;

UPDATE ${NetMRIDB}.SdnFabricDevice a
LEFT JOIN tmpSdnDeviceUpdate t ON a.SdnDeviceID = t.SdnDeviceID
SET a.DeviceID = t.NewDeviceID;

DROP TEMPORARY TABLE IF EXISTS tmpSdnDeviceUpdate;

##
## Remove any collected IPs that have a unmapped twin IP on another device.
## The unmapped twin could be the same IP (in same network), or it could be a different ip (in another network),
## but we dont know for sure until its vrf is mapped.  So until we do know, make the most likley and least risky assumption.
## We assume that the device is in the same network, and exclude it from the list.
## Assuming otherwise may result in us pummeling a single device on multiple interfaces simultaneaously, which
## has potentially seriously undesireable consequences for the device.
##

drop temporary table if exists unmappedIfAddrList;

create temporary table unmappedIfAddrList as
select a.ifIPDotted
from ${ReportDB}.ifAddr a
left join ${ReportDB}.ifConfig i on (a.InterfaceID = i.InterfaceID)
left join ${ReportDB}.VirtualNetworkMember v on (i.VirtualNetworkMemberID = v.VirtualNetworkMemberID)
where v.VirtualNetworkID = 0 or v.VirtualNetworkID is null;

alter ignore table unmappedIfAddrList add unique index (ifIPDotted);

delete n from newDeviceList n join unmappedIfAddrList u on n.IPAddress = u.ifIPDotted where n.DeviceID is null;


##
## Update discovery settings counts
##
replace into ${NetMRIDB}.Settings
(Name,Value)
select 'discovery.IPsIdentified', count(*) 
from   newDeviceList;

replace into ${NetMRIDB}.Settings
(Name,Value)
select 'discovery.IPsReachable', count(*)
from   newDeviceList d, ${NetMRIDB}.DiscoveryStatus s
where  d.DeviceID = s.DeviceID
and    ReachableStatus = 'OK';

drop temporary table if exists deviceGroupNames;

create temporary table deviceGroupNames (
DeviceID bigint unsigned not null,
GroupName varchar(64),
constraint primary key (DeviceID)
);

insert ignore into deviceGroupNames
select DeviceID, GroupName from ${ReportDB}.DeviceGroup dg, ${ReportDB}.DeviceGroupMember dm
where  dg.GroupID = dm.GroupID
order by Rank desc;	## We only want one per device and want the highest ranked group.

drop temporary table if exists IPsClassified;

create temporary table IPsClassified as
select d.DeviceID, count(*) as numClassified
from   newDeviceList d, ${NetMRIDB}.DataCollectionStatus s, ${NetMRIDB}.DiscoveryStatus ds, deviceGroupNames dg
where  d.DeviceID = s.DeviceID
and    d.DeviceID = dg.DeviceID
and    d.DeviceID = ds.DeviceID
and    SystemInd is not null
and    SystemInd != 'Error'
and    ReachableStatus = 'OK'
and    GroupName not like '%w/o SNMP'
and    GroupName != 'Network Pending'
and    GroupName != 'UNKNOWN'
and    GroupName != 'NAME ONLY'
group by d.DeviceID;

alter table IPsClassified add index(DeviceID);

replace into ${NetMRIDB}.Settings
(Name,Value)
select 'discovery.IPsClassified', sum(numClassified)
from   IPsClassified;

replace into ${NetMRIDB}.Settings
(Name,Value)
select 'discovery.IPsReachableNotClassified', count(*)
from   newDeviceList d, ${NetMRIDB}.DiscoveryStatus s
where  d.DeviceID = s.DeviceID
and    ReachableStatus = 'OK'
and    d.DeviceID not in (select DeviceID from IPsClassified);

replace into ${NetMRIDB}.Settings
(Name,Value)
select 'discovery.IPsProcessed', count(*)
from   newDeviceList d, ${NetMRIDB}.DiscoveryStatus s
where  d.DeviceID = s.DeviceID
and    SNMPCollectionStatus = 'OK'
and    ConfigCollectionStatus = 'OK';

drop temporary table if exists deviceGroupNames;

update newDeviceList n, currentDeviceList c
set    n.FirstOccurrence = IF(n.FirstOccurrence IS NULL, c.FirstOccurrence, n.FirstOccurrence)
where  n.DeviceID = c.DeviceID;

##
## Final select
##
select *
from   newDeviceList;

drop temporary table if exists newDeviceList;
drop temporary table if exists ifAddrList;
drop temporary table if exists currentDeviceList;
drop temporary table if exists tmpDeviceList;
drop temporary table if exists CidrRanges;
drop temporary table if exists hsrpAddrs;
drop temporary table if exists IPsClassified;
drop temporary table if exists tmpSdnDevices;
drop temporary table if exists tmpLWAPDevices;
drop temporary table if exists uniqueSdnDevices;
