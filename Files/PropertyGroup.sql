use netmri;

delete from PropertyGroup where dsb = 'System';

## Some "Performance" groups that collects ifTableObject are set at 25%
## ProbThreshold, however GetDevicePropertyGroups.sql will prevent it
## from collecting any of those properties other than ifTableObject

-- All Devices

insert ignore into PropertyGroup (PropertyGroup, DeviceType, Frequency, ProbThreshold, version)
values
( 'FingerPrint Device', null, 86400, 0, '201101010000' ),
( 'Path', null, 43200, 0, '201101010000'),
( 'SystemInfo', null, 10800, 0, '201101010000'),
( 'Rapid Interface Polling', null, 0, 75, '201101010000')
;

insert ignore into PropertyGroup (PropertyGroup, DeviceType, Vendor, Frequency, ProbThreshold, version)
values
-- Firewall / Security Manager Properties
( 'Firewall ARP', 'Firewall', null, 10800, 50, '201101010000'),
( 'Firewall Performance', 'Firewall', null, 900, 25, '201101010000'),
( 'Firewall Routing', 'Firewall', null, 7200, 75, '201101010000'),
( 'Security Manager ARP', 'Security Manager', null, 10800, 50, '201101010000'),
( 'Security Manager Performance', 'Security Manager', null, 900, 25, '201101010000'),
( 'Security Manager Routing', 'Security Manager', null, 7200, 75, '201101010000'),

-- Load Balancer Properties
( 'Load Balancer ARP', 'Load Balancer', null, 10800, 50, '201101010000'),
( 'Load Balancer Performance', 'Load Balancer', null, 900, 75, '201101010000'),
( 'Load Balancer Routing', 'Load Balancer', null, 7200, 75, '201101010000'),

-- Router Properties
( 'Router ARP', 'Router', null, 10800, 50, '201101010000'),
( 'Router Performance', 'Router', null, 900, 25, '201101010000'),
( 'Router Routing', 'Router', null, 7200, 75, '201101010000'),

-- Switch Properties
( 'Switch ARP', 'Switch', null, 10800, 50, '201101010000'),
( 'Switch Layer 2', 'Switch', null, 5400, 75, '201101010000'),
( 'Switch Performance', 'Switch', null, 900, 75, '201101010000'),

-- Switch-Router Properties
( 'Switch-Router ARP', 'Switch-Router', null, 10800, 50, '201101010000'),
( 'Switch-Router Layer 2', 'Switch-Router', null, 5400, 30, '201101010000'),
( 'Switch-Router Performance', 'Switch-Router', null, 900, 25, '201101010000'),
( 'Switch-Router Routing', 'Switch-Router', null, 7200, 75, '201101010000'),

-- VPN Concentrators
( 'VPN ARP', 'VPN', null, 10800, 50, '201101010000'),
( 'VPN Performance', 'VPN', null, 900, 25, '201101010000'),
( 'VPN Routing', 'VPN', null, 7200, 75, '201101010000'),

-- Wireless
( 'Wireless Config', 'Wireless AP', null, 3600, 75, '201101010000'),
( 'Wireless Performance', 'Wireless AP', null, 900, 75, '201101010000'),
( 'Symbol Config', 'Wireless AP', null, 10800, 50, '201101010000'),
( 'Symbol WOC Config', 'Wireless Controller', 'Symbol', 3600, 75, '201802230000'),
( 'Symbol WOC Forwarding', 'Wireless Controller', 'Symbol', 5400, 75, '201808023000'),
( 'Symbol WOC Performance', 'Wireless Controller', 'Symbol', 900, 75, '201808023000'),
( 'Symbol WOC Routing', 'Wireless Controller', 'Symbol', 900, 75, '201808023000'),
( 'Symbol WOC ARP', 'Wireless Controller', 'Symbol', 900, 75, '201808023000'),

-- WOC Properties
( 'WOC ARP', 'WOC', null, 10800, 50, '201101010000'),
( 'WOC Performance', 'WOC', null, 900, 25, '201101010000'),
( 'WOC Routing', 'WOC', null, 7200, 75, '201101010000')
;


insert ignore into PropertyGroup (PropertyGroup, DeviceType, Vendor, Frequency, ProbThreshold, version)
values

-- 3Com
( '3Com Config', null, '3Com', 3600, 75, '201101010000'),
( '3Com Performance', null, '3Com', 600, 75, '201101010000'),

-- Alcatel
( 'Alcatel Config', null, 'Alcatel', 3600, 75, '201101010000'),
( 'Alcatel Performance', null, 'Alcatel', 600, 75, '201101010000'),

-- Alteon
( 'Alteon Config', null, 'Alteon', 3600, 75, '201101010000'),
( 'Alteon Performance', null, 'Alteon', 600, 75, '201101010000'),

-- Aruba
( 'Aruba Config', null, 'Aruba', 3600, 30, '201101010000'),
( 'Aruba Performance', null, 'Aruba', 600, 75, '201101010000'),
( 'Aruba WOC Config', 'Wireless Controller', 'Aruba', 3600, 75, '201703100000'),
( 'Aruba WOC Forwarding', 'Wireless Controller', 'Aruba', 5400, 75, '201703100000'),
( 'Aruba WOC Performance', 'Wireless Controller', 'Aruba', 900, 75, '201703100000'),

-- Avaya
( 'Avaya Config', null, 'Avaya', 3600, 30, '201101010000'),

-- Cabletron/Enterasys 
( 'Cabletron Config', null, 'Cabletron', 3600, 75, '201101010000'),
( 'Cabletron Performance', null, 'Cabletron', 600, 75, '201101010000'),
( 'Enterasys Config', null, 'Enterasys', 3600, 75, '201101010000'),
( 'Enterasys Performance', null, 'Enterasys', 600, 75, '201101010000'),

-- Cisco
( 'Cisco Config File', null, 'Cisco', 3600, 0, '201101010000'),
( 'Cisco Firewall Performance', 'Firewall', 'Cisco', 900, 75, '201101010000'),
( 'Cisco Load Balancer Config', 'Load Balancer', 'Cisco', 3600, 75, '201101010000'),
( 'Cisco Load Balancer Forwarding', 'Load Balancer', 'Cisco', 5400, 75, '201101010000'),
( 'Cisco Performance', null, 'Cisco', 300, 75, '201101010000'),
( 'Cisco QoS Performance', null, 'Cisco', 7200, 75, '201101010000'),
( 'Cisco WOC Config', 'Wireless Controller', 'Cisco', 3600, 75, '201101010000'),
( 'Cisco WOC Forwarding', 'Wireless Controller', 'Cisco', 5400, 75, '201101010000'),
( 'Cisco WOC Performance', 'Wireless Controller', 'Cisco', 900, 75, '201208020000'),
( 'Cisco WOC Routing', 'Wireless Controller', 'Cisco', 7200, 75, '201710300000'),
( 'Cisco WOC ARP', 'Wireless Controller', 'Cisco', 10800, 50, '201710300000'),
( 'Cisco Firewall Hit Count', null, 'Cisco', 43200, 75, '201101010000'),
( 'Cisco Nexus VRF', 'Switch', 'Cisco', 7200, 75, '201708170000'),

( 'ACI Fabric Node', 'SDN Element', 'Cisco', 3600, 75, '201706150000'),
( 'ACI APIC Controller', 'SDN Controller', 'Cisco', 3600, 75, '201706150000'),

-- SDN Engine
( 'ACI Fabric Composition', 'Global', 'CISCO_APIC', 3600, 99, '201906190000'),
( 'Meraki Fabric Composition', 'Global', 'MERAKI', 3600, 99, '201906190000'),
( 'MIST Fabric Composition', 'Global', 'MIST', 3600, 99, '202210040000'),
( 'VeloCloud Fabric Composition', 'Global', 'VeloCloud', 3600, 99, '202603230000'),
( 'SilverPeak Fabric Composition', 'Global', 'SilverPeak', 3600, 99, '202405310000'),

( 'Meraki SPM', 'Global', 'MERAKI', 3600, 99, '201906190000'),
( 'Viptela Fabric Composition', 'Global', 'VIPTELA', 10800, 99, '202004020000'),
-- Type names here are provisional and will likely be changed in 7.4.2
( 'ACI Controller', 'controller', 'CISCO_APIC', 3600, 99, 201906190000),
( 'ACI Controller Monitoring', 'controller', 'CISCO_APIC', 300, 99, 201906190000),

( 'ACI Spine Monitoring', 'spine', 'CISCO_APIC', 300, 99, 201906190000),
( 'ACI Leaf Monitoring', 'leaf', 'CISCO_APIC', 300, 99, 201906190000),

( 'ACI Spine', 'spine', 'CISCO_APIC', 3600, 99, 201906190000),
( 'ACI Leaf', 'leaf', 'CISCO_APIC', 3600, 99, 201906190000),
( 'ACI Leaf SPM', 'leaf', 'CISCO_APIC', 3600, 99, 201906190000),

( 'Meraki Security', 'Meraki Security', 'MERAKI', 10800, 99, 201906260000),
( 'Meraki Switching', 'Meraki Switching', 'MERAKI', 10800, 99, 201906260000),
( 'Meraki Radios', 'Meraki Radios', 'MERAKI', 10800, 99, 201906260000),
( 'Meraki Insight', 'Meraki Insight', 'MERAKI', 10800, 99, 201906260000),
( 'Meraki Systems Manager', 'Meraki Systems Manager', 'MERAKI', 10800, 99, 201906260000),
( 'Meraki Teleworker Gateway', 'Meraki Teleworker Gateway', 'MERAKI', 10800, 99, 202010200000),

( 'Viptela Controller vmanage', 'vmanage', 'VIPTELA', 10800, 99, 202004150000),
( 'Viptela Controller vsmart', 'vsmart', 'VIPTELA', 10800, 99, 202004150000),
( 'Viptela Controller vbond', 'vbond', 'VIPTELA', 10800, 99, 202004150000),
( 'Viptela vEdge', 'vedge', 'VIPTELA', 10800, 99, 202004150000),

( 'Viptela Controller Interfaces vmanage', 'vmanage', 'VIPTELA', 3600, 99, 202004240000),
( 'Viptela Controller Interfaces vsmart', 'vsmart', 'VIPTELA', 3600, 99, 202004240000),
( 'Viptela Controller Interfaces vbond', 'vbond', 'VIPTELA', 3600, 99, 202004240000),
( 'Viptela vEdge Interfaces', 'vedge', 'VIPTELA', 3600, 99, 202004240000),

( 'Viptela Controller Performance', 'vmanage', 'VIPTELA', 3600, 99, 202005040000),
( 'Viptela Controller Performance', 'vsmart', 'VIPTELA', 3600, 99, 202005040000),
( 'Viptela Controller Performance', 'vbond', 'VIPTELA', 3600, 99, 202005040000),
( 'Viptela vEdge Performance', 'vedge', 'VIPTELA', 3600, 99, 202005040000),

-- Citrix
( 'Citrix Performance', null, 'Citrix', 600, 75, '201101010000'),

-- Extreme
( 'Extreme Config', null, 'Extreme', 3600, 75, '201101010000'),
( 'Extreme Performance', null, 'Extreme', 600, 75, '201101010000'),

-- F5
( 'F5 Config', null, 'F5', 3600, 75, '201101010000'),
( 'F5 Routing', null, 'F5', 7200, 75, '201101010000'),
( 'F5 Performance', null, 'F5', 600, 75, '201101010000'),

-- Force10
( 'Force10 Config', null, 'Force10', 3600, 75, '201101010000'),
( 'Force10 Performance', null, 'Force10', 600, 75, '201101010000'),

-- Foundry
( 'Brocade Config', null, 'Brocade', 3600, 75, '201101010000'),
( 'Brocade Performance', null, 'Brocade', 600, 75, '201101010000'),
( 'Foundry Config', null, 'Foundry', 3600, 75, '201101010000'),
( 'Foundry Performance', null, 'Foundry', 600, 75, '201101010000'),

-- HP
( 'HP Config', null, 'HP', 3600, 30, '201101010000'),
( 'HP Performance', null, 'HP', 600, 75, '201101010000'),

-- Infoblox
( 'Infoblox Config', null, 'Infoblox', 3600, 30, '201101010000'),
( 'Infoblox Performance', null, 'Infoblox', 900, 75, '201101010000'),

-- LinkSys and Dell
( 'Dell Config', null, 'Dell', 3600, 75, '201101010000'),
( 'LinkSys Config', null, 'LinkSys', 3600, 75, '201101010000'),

-- Juniper 
( 'Juniper Config', null, 'Juniper', 3600, 75, '201101010000'),
( 'Juniper Performance', null, 'Juniper', 600, 75, '201101010000'),
( 'Juniper Firewall Config', 'Firewall', 'Juniper', 3600, 75, '201101010000'),
( 'Netscreen Config', null, 'Netscreen', 3600, 75, '201101010000'),
( 'Netscreen Performance', null, 'Netscreen', 600, 75, '201101010000'),

-- Motorola
( 'Motorola Router Config', 'Router', 'Motorola', 3600, 75, '201101010000'),
( 'Motorola Router Performance', 'Router', 'Motorola', 600, 75, '201101010000'),

-- Nokia/CheckPoint
( 'CheckPoint Config', null, 'CheckPoint', 3600, 30, '201101010000'),
( 'CheckPoint Performance', null, 'CheckPoint', 600, 75, '201101010000'),

-- Nortel
( 'Contivity Config', null, 'Contivity', 3600, 75, '201101010000'),
( 'Contivity Performance', null, 'Contivity', 600, 75, '201101010000'),
( 'Nortel Config', null, 'Nortel', 3600, 30, '201101010000'),
( 'Nortel Performance', null, 'Nortel', 300, 75, '201101010000'),

-- Opengear
( 'Opengear Console Server Performance', 'Console Server', 'Opengear', 900, 75, '201706020000'),

-- PaloAlto
( 'PaloAlto Firewall Config', 'Firewall', 'PaloAltoNetworks', 3600, 75, '201101010000'),
( 'PaloAlto Firewall Performance', 'Firewall', 'PaloAltoNetworks', 600, 75, '201101010000'),

-- Riverbed
( 'Riverbed Config', null, 'Riverbed', 3600, 75, '201809070000'),
( 'Riverbed Performance', null, 'Riverbed', 600, 75, '201101010000'),

-- Riverstone 
( 'Riverstone Performance', null, 'Riverstone', 600, 75, '201101010000'),

-- SonicWALL
( 'SonicWALL Config', null, 'SonicWALL', 3600, 75, '201101010000'),
( 'SonicWALL Performance', null, 'SonicWALL', 600, 75, '201101010000'),

-- Vanguard
( 'Vanguard Config', null, 'Vanguard', 3600, 75, '201101010000'),
( 'Vanguard Performance', null, 'Vanguard', 600, 75, '201101010000'),

-- Wellfleet 
( 'Wellfleet Config', null, 'Wellfleet', 3600, 75, '201101010000'),
( 'Wellfleet Performance', null, 'Wellfleet', 600, 75, '201101010000')
;

-- Circuit Switch 
insert ignore into PropertyGroup ( PropertyGroup, DeviceType, Vendor, Frequency, ProbThreshold, version)
values
( 'Circuit Switch Performance', 'Circuit Switch', null, 900, 75, '201101010000'),

-- Comcast Video Devices
( 'Video QAM Config', 'Video QAM', null, 3600, 75, '201101010000'),
( 'Video QAM Performance', 'Video QAM', null, 900, 75, '201101010000'),

( 'Video Encoder Config', 'Video Encoder', null, 3600, 75, '201101010000'),
( 'Video Encoder Performance', 'Video Encoder', null, 900, 75, '201101010000'),

( 'Video Decoder Config', 'Video Decoder', null, 3600, 75, '201101010000'),
( 'Video Decoder Performance', 'Video Decoder', null, 900, 75, '201101010000'),

( 'Video Receiver Config', 'Video Receiver', null, 3600, 75, '201101010000'),
( 'Video Receiver Performance', 'Video Receiver', null, 900, 75, '201101010000'),

( 'Video Groomer Config', 'Video Groomer', null, 3600, 75, '201101010000'),
( 'Video Groomer Performance', 'Video Groomer', null, 900, 75, '201101010000'),

( 'Video Monitor Config', 'Video Monitor', null, 3600, 75, '201101010000'),
( 'Video Monitor Performance', 'Video Monitor', null, 900, 75, '201101010000'),

( 'CMTS Config', 'CMTS', null, 3600, 75, '201101010000'),
( 'CMTS Performance', 'CMTS', null, 900, 75, '201101010000'),

-- VoIP
( 'Cisco VoIP Call Manager Calls', 'Call Server', 'Cisco', 3600, 75, '201101010000'),
( 'Cisco VoIP Call Manager Performance', 'Call Server', 'Cisco', 900, 75, '201101010000'),
( 'Cisco VoIP Voice Mail Performance', 'Voice Mail', 'Cisco', 900, 75, '201101010000'),
( 'Cisco VoIP Gateway Routing', 'VoIP Gateway', 'Cisco', 7200, 75, '201101010000'),
( 'VoIP Gateway Performance', 'VoIP Gateway', null, 900, 75, '201101010000'),
( 'VoIP Gateway ARP', 'VoIP Gateway', null, 10800, 50, '201101010000'),
( 'Nortel VoIP Config', 'Call Server', 'Nortel', 3600, 75, '201101010000'),
( 'Nortel VoIP Performance', 'Call Server', 'Nortel', 900, 75, '201101010000')
;

replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201103210000',null,'System','HitachiCable','Hitachi Config'),
('600','75','201103210000',null,'System','HitachiCable','Hitachi Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201108230000','Load Balancer','System','A10','A10 Load Balancer Config'),
('600','75','201108230000',null,'System','A10','A10 Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201108310000','Switch','System','Dell','Dell Switch Config'),
('600','75','201108310000','Switch','System','Dell','Dell Switch Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201109230000',null,'System','Alaxala','Alaxala Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201109300000',null,'System','Fortinet','Fortinet Config'),
('600','75','201109300000',null,'System','Fortinet','Fortinet Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201110180000',null,'System','Arista','Arista Config'),
('600','75','201110180000',null,'System','Arista','Arista Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201112130000',null,'System','Stonesoft','Stonesoft Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201201210000','RADIUS Server','System','Cisco','Cisco RADIUS Server Config'),
('600','75','201201210000','RADIUS Server','System','Cisco','Cisco RADIUS Server Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('600','75','201111240000','VPN','System','SonicWALL','SonicWALL VPN Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201202070000',null,'System','Yamaha','Yamaha Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201202060000',null,'System','Yamaha','Yamaha Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201202210000',null,'System','Xirrus','Xirrus Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201202230000',null,'System','Huawei','Huawei Config'),
('600','75','201202230000',null,'System','Huawei','Huawei Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('3600','75','201112210000',null,'System','H3C','H3C Config'),
('600','75','201112210000',null,'System','H3C','H3C Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201206060000',null,'System','Avocent','Avocent Performance'),
('3600','75','201806130000',null,'System','Avocent','Avocent Config'),
('900','75','201206060000','Console Server','System',null,'Console Server Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201303020000',null,'System','BlueCoat','BlueCoat Config'),
('600','75','201303020000',null,'System','BlueCoat','BlueCoat Performance'),
('10800','30','201809100000','Proxy','System','BlueCoat','BlueCoat ARP'),
('7200','75','201809100000','Proxy','System','BlueCoat','BlueCoat Routing'),
('900','75','201303020000','Proxy','System',null,'Proxy Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201304160000',null,'System','Ruggedcom','Ruggedcom Config'),
('600','75','201304160000',null,'System','Ruggedcom','Ruggedcom Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201306040000',null,'System','Dell','Dell Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201312110000',null,'System','BNT','BNT Config'),
('600','75','201312110000',null,'System','BNT','BNT Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201405030000',null,'System','AlliedTelesyn','AlliedTelesyn Config'),
('600','75','201405030000',null,'System','AlliedTelesyn','AlliedTelesyn Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201409030000',null,'System','FireEye','FireEye Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201407170000',null,'System','Symbol','Symbol Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201407100000',null,'System','NEC','NEC Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201409250000',null,'System','AcmePacket','AcmePacket Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201502030000',null,'System','CrossbeamSystems','CrossbeamSystems Config'),
('600','75','201502030000',null,'System','CrossbeamSystems','CrossbeamSystems Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201508140000',null,'System','Citrix','Citrix Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201506090000',null,'System','Exinda','Exinda Config'),
('600','75','201506090000',null,'System','Exinda','Exinda Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201506180000',null,'System','McAfee','McAfee Config'),
('600','75','201506180000',null,'System','McAfee','McAfee Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','30','201511170000','IPS','System','Cisco','IPS ARP'),
('7200','75','201511170000','IPS','System','Cisco','IPS Routing'),
('900','75','201511170000','IPS','System','Cisco','IPS Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201507080000',null,'System','MRV','MRV Config'),
('600','75','201507080000',null,'System','MRV','MRV Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201602120000',null,'System','SEL','SEL Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201606100000','Load Balancer','System','Citrix','Citrix Load Balancer Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201605260000','Security Manager','System','Cisco','Cisco Security Manager Performance'),
('10800','30','201605260000','Security Manager','System',null,'Security Manager ARP'),
('7200','75','201605260000','Security Manager','System',null,'Security Manager Routing'),
('900','75','201605260000','Security Manager','System',null,'Security Manager Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201609020000',null,'System','Gigamon','Gigamon Config'),
('600','75','201609020000',null,'System','Gigamon','Gigamon Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201611080000',null,'System','Moxa','Moxa Config'),
('600','75','201611080000',null,'System','Moxa','Moxa Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201609280000',null,'System','AcmePacket','AcmePacket Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('7200','75','201701230000','Media Gateway','System','Avaya','Media Gateway Routing'),
('3600','75','201701230000','Media Gateway','System','Avaya','Media Gateway Config'),
('10800','30','201511170000','Media Gateway','System','Avaya','Media Gateway ARP'),
('900','75','201701230000','Media Gateway','System','Avaya','Media Gateway Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('7200','75','201608170000','Web Gateway','System',null,'Web Gateway Routing'),
('900','75','201608170000','Web Gateway','System',null,'Web Gateway Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201604270000',null,'System','Ibmnetwork','Ibmnetwork Config'),
('600','75','201604270000',null,'System','Ibmnetwork','Ibmnetwork Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201701060000',null,'System','DCN','DCN Config'),
('600','75','201701060000',null,'System','DCN','DCN Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201704140000',null,'System','Opengear','Opengear Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201702080000',null,'System','Raisecom','Raisecom Config'),
('600','75','201702080000',null,'System','Raisecom','Raisecom Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201712070000',null,'System','D-Link','D-Link Config'),
('600','75','201712070000',null,'System','D-Link','D-Link Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('3600','75','201805020000',null,'System','Samsung','Samsung Config'),
('3600','75','201805020000','Switch','System','Samsung','Samsung Switch Config'),
('600','75','201805020000',null,'System','Samsung','Samsung Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201803030000',null,'System','CumulusNetworks','CumulusNetworks Config'),
('600','75','201803030000',null,'System','CumulusNetworks','CumulusNetworks Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','30','201806120000','Time Server','System','Spectracom','Spectracom ARP'),
('7200','75','201806120000','Time Server','System','Spectracom','Spectracom Routing'),
('3600','75','201806120000','Time Server','System','Spectracom','Spectracom Config'),
('600','75','201806120000','Time Server','System','Spectracom','Spectracom Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','201704110000','UPS','System','Emerson','Emerson Performance'),
('3600','75','201704110000','UPS','System','Emerson','Emerson Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('10800','30','201806190000','Storage Appliance','System','Cisco','Storage Appliance ARP'),
('7200','75','201806190000','Storage Appliance','System','Cisco','Storage Appliance Routing'),
('900','75','201806190000','Storage Appliance','System','Cisco','Storage Appliance Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201803200000',null,'System','APCON','APCON Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201810310000',null,'System','ArrayNetworks','ArrayNetworks Config'),
('600','75','201810310000','Load Balancer','System','ArrayNetworks','ArrayNetworks Load Balancer Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201805140000',null,'System','Talari','Talari Config'),
('600','75','201805140000','SD-WAN','System','Talari','Talari SD-WAN Performance'),
('10800','30','201805140000','SD-WAN','System',null,'SD-WAN ARP'),
('7200','75','201805140000','SD-WAN','System',null,'SD-WAN Routing'),
('900','75','201805140000','SD-WAN','System',null,'SD-WAN Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','75','201809070000',null,'System','Viptela','Viptela Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201901080000',null,'System','Ciena','Ciena Config'),
('600','75','201901080000',null,'System','Ciena','Ciena Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201904100000',null,'System','Meraki','Meraki Config'),
('900','75','201904100000','Cloud Switch','System',null,'Cloud Switch Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201902250000',null,'System','Anue','Anue Config'),
('900','75','201902250000','NTO','System',null,'NTO Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','30','201807130000','Visibility Appliance','System',null,'Gigamon Appliance ARP'),
('7200','75','201807130000','Visibility Appliance','System',null,'Gigamon Appliance Routing'),
('900','75','201807130000','Visibility Appliance','System',null,'Gigamon Appliance Performance'),
('10800','30','201807130000','Traffic Aggregation Node','System',null,'Gigamon Appliance ARP'),
('7200','75','201807130000','Traffic Aggregation Node','System',null,'Gigamon Appliance Routing'),
('900','75','201807130000','Traffic Aggregation Node','System',null,'Gigamon Appliance Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('600','75','201907090000','Security-Appliance','System','Fortinet','Fortinet Security-Appliance Performance'),
('10800','30','201907090000','Security-Appliance','System',null,'Security-Appliance ARP'),
('7200','75','201907090000','Security-Appliance','System',null,'Security-Appliance Routing'),
('900','75','201907090000','Security-Appliance','System',null,'Security-Appliance Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201809140000',null,'System','ZTE','ZTE Config'),
('600','75','201809140000',null,'System','ZTE','ZTE Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201904030000',null,'System','Uplogix','Uplogix Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('5400','75','201910020000','Load Balancer','System','Citrix','Citrix Load Balancer L2');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201809190000',null,'System','Transition','Transition Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','201910080000',null,'System','ServerTech','ServerTech Config'),
('7200','75','201910080000','PDU','System',null,'PDU Routing'),
('900','75','201910080000','PDU','System',null,'PDU Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','202003030000',null,'System','BSN','BSN Performance'),
('3600','75','202003030000',null,'System','BSN','BSN Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('7200','75','202002020000',null,'System','APC','APC Routing'),
('7200','75','202002020000',null,'System','APC','APC ARP'),
('900','75','202002020000',null,'System','APC','APC Performance'),
('3600','75','202002020000',null,'System','APC','APC Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202003310000','Server','System','Cisco','Cisco Server Config'),
('10800','30','202003310000','Server','System',null,'Server ARP'),
('7200','75','202003310000','Server','System',null,'Server Routing'),
('900','75','202003310000','Server','System',null,'Server Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('900','75','201906260000','Cloud AP','System',null,'Cloud AP Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','30','202009110000','Service Delivery Platform','System',null,'Service Delivery Platform ARP'),
('7200','75','202009110000','Service Delivery Platform','System',null,'Service Delivery Platform Routing'),
('900','75','202009110000','Service Delivery Platform','System',null,'Service Delivery Platform Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('10800','30','202009010000',null,'System','Infinera','Infinera ARP'),
('7200','75','202009010000',null,'System','Infinera','Infinera Routing'),
('3600','75','202009010000',null,'System','Infinera','Infinera Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202010020000',null,'System','Ubiquiti','Ubiquiti Config'),
('7200','75','202010020000',null,'System','Ubiquiti','Ubiquiti Routing'),
('600','75','202010020000',null,'System','Ubiquiti','Ubiquiti Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202006080000',null,'System','Coriant','Coriant Config'),
('900','75','202006080000',null,'System','Coriant','Coriant Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('3600','75','202102190000',null,'System','SilverPeak','SilverPeak Config'),
('600','75','202102190000',null,'System','SilverPeak','SilverPeak Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','202008250000',null,'System','Riverbed','Riverbed Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202104140000',null,'System','Alaxala','Alaxala Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202108110000',null,'System','StormShield','StormShield Config'),
('600','75','202108110000',null,'System','StormShield','StormShield Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202108170000',null,'System','Pulse Secure','Pulse Secure Config'),
('600','75','202108170000',null,'System','Pulse Secure','Pulse Secure Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202109270000',null,'System','Cloudgenix','Cloudgenix Config'),
('600','75','202109270000','SD-WAN','System','Cloudgenix','Cloudgenix SD-WAN Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202108100000',null,'System','Riverbed','Riverbed Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202106140000',null,'System','Furukawa','Furukawa Config'),
('600','75','202106140000',null,'System','Furukawa','Furukawa Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202109290000',null,'System','Brocade','Brocade Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202112200000',null,'System','A10','A10 Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('600','75','202107200000',null,'System','Viptela','Viptela Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202009070000',null,'System','Fokus','Fokus Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values
('3600','75','202109010000',null,'System','Raritan','Raritan Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202109220000',null,'System','Mellanox','Mellanox Config'),
('600','75','202109220000',null,'System','Mellanox','Mellanox Performance');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202112160000',null,'System','H3C','H3C Config');
replace into PropertyGroup
(Frequency,ProbThreshold,version,DeviceType,dsb,Vendor,PropertyGroup) values 
('3600','75','202301040000','UPS','System','Eaton','Eaton UPS Config');
replace into PropertyGroup
(Frequency,version,dsb,PropertyGroup,DeviceType,Vendor,ProbThreshold) values 
('3600','202407230000','System','Cisco Security Manager Config','Security Manager','Cisco','75');
replace into PropertyGroup
(Vendor,PropertyGroup,Frequency,DeviceType,ProbThreshold,dsb,version) values 
('CheckPoint','CheckPoint Config','3600',null,'75','System','202410150000');
replace into PropertyGroup
(PropertyGroup,Vendor,Frequency,ProbThreshold,dsb,DeviceType,version) values 
('Extreme Config','Extreme','3600','75','System',null,'202502030000');
replace into PropertyGroup
(ProbThreshold,Frequency,version,dsb,PropertyGroup,DeviceType,Vendor) values 
('75','3600','202503140000','System','Cisco Config',null,'Cisco');
replace into PropertyGroup
(Vendor,Frequency,dsb,PropertyGroup,version,ProbThreshold,DeviceType) values 
('Cisco','3600','System','Cisco Config','202411250000','75',null);
replace into PropertyGroup
(version,dsb,Vendor,PropertyGroup,DeviceType,Frequency,ProbThreshold) values 
('202404070000','System','Cisco','Cisco Config',null,'3600','75');
replace into PropertyGroup
(Frequency,Vendor,PropertyGroup,DeviceType,dsb,version,ProbThreshold) values 
('3600','HP','HP Config',null,'System','202407190000','75');
replace into PropertyGroup
(DeviceType,ProbThreshold,dsb,Frequency,PropertyGroup,Vendor,version) values 
(null,'75','System','3600','Extreme Config','Extreme','202402010000');
replace into PropertyGroup
(dsb,ProbThreshold,DeviceType,Vendor,version,Frequency,PropertyGroup) values 
('System','75',null,'Alcatel','202306040000','3600','Alcatel Config');
replace into PropertyGroup
(DeviceType,Frequency,Vendor,version,ProbThreshold,PropertyGroup,dsb) values 
(null,'3600','HP','202306150000','75','HP Config','System');
replace into PropertyGroup
(DeviceType,Frequency,version,ProbThreshold,dsb,PropertyGroup,Vendor) values 
(null,'3600','202203030000','75','System','Raisecom Config','Raisecom');
replace into PropertyGroup
(dsb,version,Vendor,ProbThreshold,Frequency,PropertyGroup,DeviceType) values 
('System','202201240000','Extreme','75','3600','Extreme Config',null),
('System','202201240000','Extreme','75','600','Extreme Performance',null);
replace into PropertyGroup
(PropertyGroup,ProbThreshold,dsb,Vendor,version,Frequency,DeviceType) values 
('Huawei Config','75','System','Huawei','202207010000','3600',null);
replace into PropertyGroup
(PropertyGroup,Frequency,DeviceType,ProbThreshold,dsb,Vendor,version) values 
('Dionis Config','3600',null,'75','System','Dionis','202301240000');
replace into PropertyGroup
(ProbThreshold,version,dsb,DeviceType,PropertyGroup,Vendor,Frequency) values 
('75','202405050000','System',null,'Netgear Config','Netgear','3600');
replace into PropertyGroup
(ProbThreshold,version,DeviceType,PropertyGroup,dsb,Frequency,Vendor) values 
('75','202405090000',null,'LavelleNetworks Performance','System','600','LavelleNetworks');
replace into PropertyGroup
(Frequency,PropertyGroup,dsb,version,Vendor,ProbThreshold,DeviceType) values 
('3600','Versa Config','System','202410300000','Versa','75',null);
replace into PropertyGroup
(dsb,Vendor,DeviceType,Frequency,PropertyGroup,ProbThreshold,version) values 
('System','VMWare',null,'3600','VMWare Config','75','202405200000');
replace into PropertyGroup
(version,DeviceType,dsb,ProbThreshold,PropertyGroup,Vendor,Frequency) values 
('202402260000',null,'System','75','Nortel Config','Nortel','3600');
replace into PropertyGroup
(dsb,ProbThreshold,Frequency,PropertyGroup,DeviceType,Vendor,version) values 
('System','75','3600','HP Wireless AP Config','Wireless AP','HP','202302220000');
replace into PropertyGroup
(ProbThreshold,PropertyGroup,Frequency,version,DeviceType,dsb,Vendor) values 
('75','PaloAltoNetworks Config','3600','202506100000',null,'System','PaloAltoNetworks');
replace into PropertyGroup
(ProbThreshold,Vendor,Frequency,version,PropertyGroup,DeviceType,dsb) values 
('75','Tejas','3600','202504020000','Tejas Config',null,'System'),
('75','Tejas','600','202504020000','Tejas Performance',null,'System');
replace into PropertyGroup
(ProbThreshold,DeviceType,PropertyGroup,Frequency,Vendor,version,dsb) values 
('75','Cloud-Hypervisor','Cisco Cloud-Hypervisor Performance','600','Cisco','202304060000','System');
replace into PropertyGroup
(PropertyGroup,dsb,version,DeviceType,Frequency,ProbThreshold,Vendor) values 
('ZPE Console Server Config','System','202307240000','Console Server','3600','75','ZPE'),
('ZPE Performance','System','202307240000',null,'600','75','ZPE');
