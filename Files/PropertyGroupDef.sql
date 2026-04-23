use netmri;

delete from PropertyGroupDef where dsb = 'System';

## If you add any properties to Firewall Performance, Router Performance,
## Switch-Router Performance, or VPN Performance, think about creating
## a new property group instead.  These groups are now getting dispatched
## at 25% probability and the stuff you are adding should be waiting until
## 75%.


insert ignore into PropertyGroupDef (PropertyGroup, PropertyName, Source, version)
values

-- -------------------------------------------------------------------------
-- SystemInfo

('Rapid Interface Polling', 'rapidIfTableObject', 'Net-SNMP', '201101010000'),
('SystemInfo', 'SystemInfo', 'Net-SNMP', '201101010000'),
('SNMP Credential Check', 'CredentialCollector', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Firewall / Security Manager Properties

('Firewall ARP', 'atObject', 'Net-SNMP', '201101010000'),
('Security Manager ARP', 'atObject', 'Net-SNMP', '201101010000'),

('Firewall Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Security Manager Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('Firewall Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Firewall Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('Firewall Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),
('Firewall Routing', 'DeviceContext', 'Net-SNMP', '201101010000'),
('Firewall Routing', 'VrfObject', 'Net-SNMP', '201402250000'),

('Security Manager Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Security Manager Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('Security Manager Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Load Balancer Properties

('Load Balancer ARP', 'atObject', 'Net-SNMP', '201101010000'),

('Load Balancer Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('Load Balancer Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Load Balancer Routing', 'DeviceContext', 'Net-SNMP', '201101010000'),

('Load Balancer Routing', 'DeviceContext', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Router Properties

('Router ARP', 'atObject', 'Net-SNMP', '201101010000'),

('Router Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('Router Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Router Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('Router Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),
('Router Routing', 'DeviceContext', 'Net-SNMP', '201101010000'),
('Router Routing', 'VrfObject', 'Net-SNMP', '201402250000'),

-- -------------------------------------------------------------------------
-- Switch Properties

('Switch ARP', 'atObject', 'Net-SNMP', '201101010000'),

('Switch Layer 2', 'ForwardingObject', 'Net-SNMP', '201101010000'),
('Switch Layer 2', 'SwitchPortObject', 'Net-SNMP', '201101010000'),
('Switch Layer 2', 'VlanObject', 'Net-SNMP', '201101010000'),

('Switch Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Switch-Router Properties

('Switch-Router ARP', 'atObject', 'Net-SNMP', '201101010000'),

('Switch-Router Layer 2', 'ForwardingObject', 'Net-SNMP', '201101010000'),
('Switch-Router Layer 2', 'SwitchPortObject', 'Net-SNMP', '201101010000'),
('Switch-Router Layer 2', 'VlanObject', 'Net-SNMP', '201101010000'),

('Switch-Router Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('Switch-Router Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Switch-Router Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('Switch-Router Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),
('Switch-Router Routing', 'DeviceContext', 'Net-SNMP', '201101010000'),
('Switch-Router Routing', 'VrfObject', 'Net-SNMP', '201402250000'),

-- -------------------------------------------------------------------------
-- VPN Properties

('VPN ARP', 'atObject', 'Net-SNMP', '201101010000'),

('VPN Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('VPN Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('VPN Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('VPN Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Wireless Properties

('Wireless Config', 'WirelessObject', 'Net-SNMP', '201101010000'),

('Wireless Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('Symbol Config', 'atObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- WOC Properties

('WOC ARP', 'atObject', 'Net-SNMP', '201101010000'),

('WOC Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),

('WOC Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('WOC Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('WOC Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000')
;

insert ignore into PropertyGroupDef
(PropertyGroup, PropertyName, Source, version)
values

-- -------------------------------------------------------------------------
-- 3Com

('3Com Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('3Com Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Alcatel

('Alcatel Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Alcatel Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Alcatel Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Alteon

('Alteon Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Alteon Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Aruba

('Aruba Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Aruba Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Aruba Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Aruba WOC Config', 'VlanObject', 'Net-SNMP', '201703100000'),
('Aruba WOC Config', 'SwitchPortObject', 'Net-SNMP', '201703100000'),
('Aruba WOC Config', 'WirelessObject', 'Net-SNMP', '201703100000'),
('Aruba WOC Config', 'atObject', 'Net-SNMP', '201806070000'),
('Aruba WOC Config', 'ipRouteTableObject', 'Net-SNMP', '201806070000'),

('Aruba WOC Forwarding', 'ForwardingObject', 'Net-SNMP', '201703100000'),
('Aruba WOC Performance', 'ifTableObject', 'Net-SNMP', '201703100000'),

-- -------------------------------------------------------------------------
-- Avaya
('Avaya Config', 'Environmental', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Avocent

('Avocent Config', 'atObject', 'Net-SNMP', '201808210000'),
('Avocent Config', 'ipRouteTableObject', 'Net-SNMP', '201808210000'),

-- -------------------------------------------------------------------------
-- Cabletron/Enterasys

('Cabletron Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Cabletron Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Cabletron Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Enterasys Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Enterasys Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Enterasys Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- CheckPoint

('CheckPoint Config', 'Environmental', 'Net-SNMP', '201101010000'),
('CheckPoint Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('CheckPoint Config', 'NokiaObject', 'Net-SNMP', '201101010000'),
('CheckPoint Config', 'Firewall', 'Net-SNMP', '201809190000'),

('CheckPoint Performance', 'CheckPointObject', 'Net-SNMP', '201101010000'),
('CheckPoint Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Cisco

('Cisco Firewall Performance', 'CiscoFirewall', 'Net-SNMP', '201101010000'),

('Cisco Firewall Hit Count', 'FirewallHitCount', 'Net-SNMP', '201206010000'),

('Cisco Load Balancer Config', 'SwitchPortObject', 'Net-SNMP', '201101010000'),
('Cisco Load Balancer Config', 'VlanObject', 'Net-SNMP', '201101010000'),

('Cisco Load Balancer Forwarding', 'ForwardingObject', 'Net-SNMP', '201101010000'),

('Cisco Performance', 'CiscoBufferObject', 'Net-SNMP', '201101010000'),
('Cisco Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Cisco QoS Performance', 'QoSObject',  'Net-SNMP', '201101010000'),

('Cisco WOC Config', 'VlanObject', 'Net-SNMP', '201101010000'),
('Cisco WOC Config', 'SwitchPortObject', 'Net-SNMP', '201101010000'),
('Cisco WOC Config', 'WirelessObject', 'Net-SNMP', '201101010000'),

('Cisco WOC Forwarding', 'ForwardingObject', 'Net-SNMP', '201101010000'),
('Cisco WOC Performance', 'ifTableObject', 'Net-SNMP', '201208020000'),

('Cisco WOC ARP', 'atObject', 'Net-SNMP', '201710300000'),

('Cisco WOC Routing', 'ipRouteTableObject', 'Net-SNMP', '201710300000'),
('Cisco WOC Routing', 'RoutingInfo', 'Net-SNMP', '201710300000'),
('Cisco WOC Routing', 'RoutingPerfObject', 'Net-SNMP', '201710300000'),

('Cisco Nexus VRF', 'VrfObject', 'Net-SNMP', '201803300000'),

-- SDN Engine
('ACI Fabric Composition', 'obtainDevices', 'SDN', '201906190000'),
('ACI Fabric Composition', 'obtainAciPolicyObjects', 'SDN', '201906190000'),

('ACI Controller', 'obtainSystemInfo', 'SDN', 201906190000),
('ACI Controller', 'obtainInventory', 'SDN', 201906190000),
('ACI Controller', 'obtainInterfaces', 'SDN', 201906190000),
('ACI Controller', 'obtainTopology', 'SDN', 202205260000),

('ACI Controller Monitoring', 'obtainPerformance', 'SDN', 201906190000),
('ACI Controller Monitoring', 'obtainEnvironmental', 'SDN', 201906190000),
('ACI Spine Monitoring', 'obtainPerformance', 'SDN', 201906190000),
('ACI Spine Monitoring', 'obtainEnvironmental', 'SDN', 201906190000),
('ACI Leaf Monitoring', 'obtainPerformance', 'SDN', 201906190000),
('ACI Leaf Monitoring', 'obtainEnvironmental', 'SDN', 201906190000),

('ACI Leaf', 'obtainSystemInfo', 'SDN', 201906190000),
('ACI Leaf', 'obtainInventory', 'SDN', 201906190000),
('ACI Leaf', 'obtainInterfaces', 'SDN', 201906190000),
('ACI Leaf', 'obtainIPAddress', 'SDN', 201906190000),
('ACI Leaf', 'obtainVrf', 'SDN', 201906190000),
('ACI Leaf', 'obtainVrfHasInterface', 'SDN', 201906190000),
('ACI Leaf', 'obtainRoute', 'SDN', 201906190000),
('ACI Leaf', 'obtainVlan', 'SDN', 201906190000),
('ACI Leaf', 'obtainCdp', 'SDN', 201906190000),
('ACI Leaf', 'obtainLldp', 'SDN', 201906190000),
('ACI Leaf', 'obtainTopology', 'SDN', 202206030000),

('ACI Spine', 'obtainSystemInfo', 'SDN', 201906190000),
('ACI Spine', 'obtainInventory', 'SDN', 201906190000),
('ACI Spine', 'obtainInterfaces', 'SDN', 201906190000),
('ACI Spine', 'obtainIPAddress', 'SDN', 201906190000),
('ACI Spine', 'obtainVrf', 'SDN', 201906190000),
('ACI Spine', 'obtainVrfHasInterface', 'SDN', 201906190000),
('ACI Spine', 'obtainRoute', 'SDN', 201906190000),
('ACI Spine', 'obtainLldp', 'SDN', 201906190000),
('ACI Spine', 'obtainCdp', 'SDN', 201906190000),
('ACI Spine', 'obtainTopology', 'SDN', 202206030000),

('ACI Leaf SPM', 'obtainEndhosts', 'SDN', 201906190000),

('Meraki Fabric Composition', 'obtainDevices', 'SDN', '201906190000'),
('MIST Fabric Composition', 'obtainEverything', 'SDN', '202210040000'),
('VeloCloud Fabric Composition', 'obtainEverything', 'SDN', '202603240000'),
('MIST Fabric Composition', 'obtainEndhosts', 'SDN', '202210040000'),

('SilverPeak Fabric Composition', 'obtainDevices', 'SDN', '202406070000'),
('SilverPeak Fabric Composition', 'obtainSystemInfo', 'SDN', '202406070000'),
('SilverPeak Fabric Composition', 'obtainEverything', 'SDN', '202406070000'),

('Meraki SPM', 'obtainEndhosts', 'SDN', '201908210000'),

('Meraki Security', 'obtainEverything', 'SDN', 201906260000),
('Meraki Switching', 'obtainEverything', 'SDN', 201906260000),
('Meraki Radios', 'obtainEverything', 'SDN', 201906260000),
('Meraki Insight', 'obtainEverything', 'SDN', 201906260000),
('Meraki Systems Manager', 'obtainEverything', 'SDN', 201906260000),
('Meraki Teleworker Gateway', 'obtainEverything', 'SDN', 202010200000),
('Meraki Radios', 'obtainSystemInfo', 'SDN', '20210601000000'),
('Meraki Security', 'obtainSystemInfo', 'SDN', '20210601000000'),
('Meraki Switching', 'obtainSystemInfo', 'SDN', '20210601000000'),

('Viptela Fabric Composition', 'obtainDevices', 'SDN', '202004020000'),
('Viptela Controller vmanage', 'obtainSystemInfo', 'SDN', '202004150000'),
('Viptela Controller vsmart', 'obtainSystemInfo', 'SDN', '202004150000'),
('Viptela Controller vbond', 'obtainSystemInfo', 'SDN', '202004150000'),
('Viptela vEdge', 'obtainSystemInfo', 'SDN', '202004150000'),

('Viptela Controller vmanage', 'obtainRoute', 'SDN', '202004290000'),
('Viptela Controller vsmart', 'obtainRoute', 'SDN', '202004290000'),
('Viptela Controller vbond', 'obtainRoute', 'SDN', '202004290000'),
('Viptela vEdge', 'obtainRoute', 'SDN', '202004290000'),

('Viptela Controller vmanage', 'obtainEnvironment', 'SDN', '202005140000'),
('Viptela Controller vsmart', 'obtainEnvironment', 'SDN', '202005140000'),
('Viptela Controller vbond', 'obtainEnvironment', 'SDN', '202005140000'),
('Viptela vEdge', 'obtainEnvironment', 'SDN', '202005140000'),

('Viptela Controller vmanage', 'obtainArp', 'SDN', '202004300000'),
('Viptela Controller vsmart', 'obtainArp', 'SDN', '202004300000'),
('Viptela Controller vbond', 'obtainArp', 'SDN', '202004300000'),
('Viptela vEdge', 'obtainArp', 'SDN', '202004300000'),

('Viptela Controller Interfaces vmanage', 'obtainInterfaces', 'SDN', '202004240000'),
('Viptela Controller Interfaces vsmart', 'obtainInterfaces', 'SDN', '202004240000'),
('Viptela Controller Interfaces vbond', 'obtainInterfaces', 'SDN', '202004240000'),
('Viptela vEdge Interfaces', 'obtainInterfaces', 'SDN', '202004240000'),

('Viptela Controller Performance', 'obtainPerformance', 'SDN', '202005040000'),
('Viptela vEdge Performance', 'obtainPerformance', 'SDN', '202005040000'),

-- -------------------------------------------------------------------------
-- Citrix

('Citrix Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Extreme

('Extreme Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Extreme Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Extreme Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- F5

('F5 Config', 'F5Object', 'Net-SNMP', '201101010000'),
('F5 Config', 'Environmental', 'Net-SNMP', '201101010000'),

('F5 Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Force10

('Force10 Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Force10 Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Force10 Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Foundry/Brocade

('Brocade Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Brocade Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Brocade Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Foundry Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Foundry Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Foundry Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- HP

('HP Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('HP Config', 'Environmental', 'Net-SNMP', '201101010000'),

('HP Performance', 'HpBufferObject', 'Net-SNMP', '201101010000'),
('HP Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Infoblox

('Infoblox Config', 'atObject', 'Net-SNMP', '201101010000'),
('Infoblox Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Infoblox Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Infoblox Config', 'InfobloxObject', 'Net-SNMP', '201101010000'),
('Infoblox Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Infoblox Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Infoblox Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Juniper

('Juniper Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Juniper Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Juniper Firewall Config', 'Firewall', 'Net-SNMP', '201101010000'),

('Juniper Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Netscreen Config', 'Firewall', 'Net-SNMP', '201101010000'),
('Netscreen Config', 'NetscreenObject', 'Net-SNMP', '201101010000'),

('Netscreen Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- LinkSys & Dell

('LinkSys Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Dell Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Motorola

('Motorola Router Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Motorola Router Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Motorola Router Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Nortel

('Contivity Config', 'InventoryObject', 'Net-SNMP', '201101010000'),

('Contivity Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

('Nortel Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Nortel Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Nortel Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- --------------------------------------------------------------------------
-- Opengear
('Opengear Console Server Performance', 'PerformanceObject', 'Net-SNMP', '201706020000'),

-- -------------------------------------------------------------------------
-- PaloAlto

('PaloAlto Firewall Config', 'Environmental', 'Net-SNMP', '201101010000'),
('PaloAlto Firewall Config', 'Firewall', 'Net-SNMP', '201101010000'),
('PaloAlto Firewall Config', 'InventoryObject', 'Net-SNMP', '202601300000'),

('PaloAlto Firewall Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Riverbed

('Riverbed Config', 'InventoryObject', 'Net-SNMP', '201809070000'),
('Riverbed Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Riverstone

('Riverstone Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- SonicWALL

('SonicWALL Config', 'Firewall', 'Net-SNMP', '201101010000'),

('SonicWALL Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Symbol

('Symbol WOC Config', 'VlanObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Config', 'SwitchPortObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Config', 'WirelessObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Config', 'InventoryObject', 'Net-SNMP', '201802230000'),

('Symbol WOC Forwarding', 'ForwardingObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Performance', 'ifTableObject', 'Net-SNMP', '201802230000'),
('Symbol WOC ARP', 'atObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Routing', 'ipRouteTableObject', 'Net-SNMP', '201802230000'),
('Symbol WOC Routing', 'RoutingInfo', 'Net-SNMP', '201802230000'),

-- -------------------------------------------------------------------------
-- Vanguard

('Vanguard Config', 'ForwardingObject', 'Net-SNMP', '201101010000'),

('Vanguard Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),

-- -------------------------------------------------------------------------
-- Wellfleet

('Wellfleet Config', 'Environmental', 'Net-SNMP', '201101010000'),

('Wellfleet Performance', 'PerformanceObject', 'Net-SNMP', '201101010000')
;

-- Circuit Switch
insert ignore into PropertyGroupDef (PropertyGroup, PropertyName, Source, version)
values
('Circuit Switch Performance', 'CircuitSwitch', 'Net-SNMP', '201101010000'),
('Circuit Switch Performance', 'ifTableObject', 'Net-SNMP', '201101010000')
;

-- Comcast Video Devices
insert ignore into PropertyGroupDef (PropertyGroup, PropertyName, Source, version)
values 
('Video QAM Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video QAM Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video QAM Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video QAM Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video QAM Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video QAM Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('Video Encoder Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video Encoder Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video Encoder Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video Encoder Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video Encoder Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video Encoder Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('Video Decoder Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video Decoder Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video Decoder Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video Decoder Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video Decoder Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video Decoder Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('Video Receiver Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video Receiver Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video Receiver Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video Receiver Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video Receiver Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video Receiver Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('Video Groomer Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video Groomer Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video Groomer Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video Groomer Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video Groomer Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video Groomer Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('Video Monitor Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Video Monitor Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Video Monitor Config', 'atObject', 'Net-SNMP', '201101010000'),
('Video Monitor Config', 'Environmental', 'Net-SNMP', '201101010000'),
('Video Monitor Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Video Monitor Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),

('CMTS Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('CMTS Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('CMTS Config', 'atObject', 'Net-SNMP', '201101010000'),
('CMTS Config', 'Environmental', 'Net-SNMP', '201101010000'),
('CMTS Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('CMTS Config', 'ipRouteTableObject', 'Net-SNMP', '201101010000')
;

-- VoIP
insert ignore into PropertyGroupDef (PropertyGroup, PropertyName, Source, version)
values 
('Cisco VoIP Responder', 'voipResponderObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Test', 'voipTestObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Call Manager Calls', 'CiscoCallMgrObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Call Manager Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Call Manager Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Voice Mail Performance', 'PerformanceObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Voice Mail Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Gateway Routing', 'ipRouteTableObject', 'Net-SNMP', '201101010000'),
('Cisco VoIP Gateway Routing', 'RoutingInfo', 'Net-SNMP', '201101010000'),
('Cisco VoIP Gateway Routing', 'RoutingPerfObject', 'Net-SNMP', '201101010000'),
('VoIP Gateway Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('VoIP Gateway ARP', 'atObject', 'Net-SNMP', '201101010000'),
('Nortel VoIP Config', 'InventoryObject', 'Net-SNMP', '201101010000'),
('Nortel VoIP Performance', 'ifTableObject', 'Net-SNMP', '201101010000'),
('Nortel VoIP Performance', 'PerformanceObject', 'Net-SNMP', '201101010000')
;

-- Non-SNMP Properties

insert ignore into PropertyGroupDef (PropertyGroup, PropertyName, Source, version)
values
('FingerPrint Device', 'sysDescr', 'FingerPrint', '201101010000'),
('FingerPrint Device', 'sysName', 'FingerPrint', '201101010000'),

('Path', 'sysDescr', 'Path', '201101010000'),
('Path', 'TTL', 'Path', '201101010000'),
('Path', 'ResponseTime', 'Path', '201101010000')
;
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201103210000','System','Net-SNMP','Environmental','Hitachi Config'),
('201103210000','System','Net-SNMP','PerformanceObject','Hitachi Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201108230000','System','Net-SNMP','Environmental','A10 Load Balancer Config'),
('202003170000','System','Net-SNMP','VlanObject','A10 Load Balancer Config'),
('202003170000','System','Net-SNMP','SwitchPortObject','A10 Load Balancer Config'),
('201108230000','System','Net-SNMP','PerformanceObject','A10 Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201108310000','System','Net-SNMP','Environmental','Dell Config'),
('201108310000','System','Net-SNMP','PerformanceObject','Dell Switch Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201109230000','System','Net-SNMP','Environmental','Alaxala Config'),
('201109230000','System','Net-SNMP','PerformanceObject','Alaxala Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201109300000','System','Net-SNMP','InventoryObject','Fortinet Config'),
('201109300000','System','Net-SNMP','PerformanceObject','Fortinet Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201110180000','System','Net-SNMP','InventoryObject','Arista Config'),
('201110180000','System','Net-SNMP','Environmental','Arista Config'),
('201110180000','System','Net-SNMP','PerformanceObject','Arista Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201112130000','System','Net-SNMP','PerformanceObject','Stonesoft Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201201100002','System','Net-SNMP','InventoryObject','Aruba Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201201210000','System','Net-SNMP','InventoryObject','Cisco RADIUS Server Config'),
('201201210000','System','Net-SNMP','PerformanceObject','Cisco RADIUS Server Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201111240000','System','Net-SNMP','PerformanceObject','SonicWALL VPN Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201202070000','System','Net-SNMP','PerformanceObject','Yamaha Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201202060000','System','Net-SNMP','Environmental','Yamaha Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201201200000','System','Net-SNMP','VlanObject','F5 Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201201270000','System','Net-SNMP','PerformanceObject','Extreme Switch Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201202210000','System','Net-SNMP','InventoryObject','Xirrus Config'),
('201202210000','System','Net-SNMP','Environmental','Xirrus Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201206080000','System','Net-SNMP','SwitchPortObject','Juniper Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201202230000','System','Net-SNMP','InventoryObject','Huawei Config'),
('201202230000','System','Net-SNMP','VlanObject','Huawei Config'),
('201202230000','System','Net-SNMP','ForwardingObject','Huawei Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201207080000','System','Net-SNMP','SwitchPortObject','3Com Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201208200000','System','Net-SNMP','Environmental','Huawei Config'),
('201208200000','System','Net-SNMP','SwitchPortObject','Huawei Config'),
('201208200000','System','Net-SNMP','PerformanceObject','Huawei Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201112210000','System','Net-SNMP','InventoryObject','H3C Config'),
('201112210000','System','Net-SNMP','Environmental','H3C Config'),
('201112210000','System','Net-SNMP','VlanObject','H3C Config'),
('201911150000','System','Net-SNMP','VrfObject','H3C Config'),
('201112210000','System','Net-SNMP','PerformanceObject','H3C Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201206060000','System','Net-SNMP','PerformanceObject','Avocent Performance'),
('201206060000','System','Net-SNMP','ifTableObject','Console Server Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201209140000','System','Net-SNMP','ForwardingObject','Dell Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201211290000','System','Net-SNMP','Environmental','Netscreen Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201303020000','System','Net-SNMP','Firewall','BlueCoat Config'),
('201303020000','System','Net-SNMP','Environmental','BlueCoat Config'),
('201303020000','System','Net-SNMP','PerformanceObject','BlueCoat Performance'),
('201809100000','System','Net-SNMP','atObject','BlueCoat ARP'),
('201809100000','System','Net-SNMP','ipRouteTableObject','BlueCoat Routing'),
('201303020000','System','Net-SNMP','ifTableObject','Proxy Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201304160000','System','Net-SNMP','InventoryObject','Ruggedcom Config'),
('201304160000','System','Net-SNMP','Environmental','Ruggedcom Config'),
('201304160000','System','Net-SNMP','VlanObject','Ruggedcom Config'),
('201304160000','System','Net-SNMP','ForwardingObject','Ruggedcom Config'),
('201304160000','System','Net-SNMP','SwitchPortObject','Ruggedcom Config'),
('201304160000','System','Net-SNMP','PerformanceObject','Ruggedcom Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201302070000','System','Net-SNMP','ForwardingObject','H3C Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201309020000','System','Net-SNMP','SwitchPortObject','Alcatel Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201306040000','System','Net-SNMP','VlanObject','Dell Config'),
('201306040000','System','Net-SNMP','SwitchPortObject','Dell Config'),
('201306040000','System','Net-SNMP','PerformanceObject','Dell Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201312110000','System','Net-SNMP','Environmental','BNT Config'),
('201312110000','System','Net-SNMP','VlanObject','BNT Config'),
('201312110000','System','Net-SNMP','ForwardingObject','BNT Config'),
('201312110000','System','Net-SNMP','SwitchPortObject','BNT Config'),
('201312110000','System','Net-SNMP','PerformanceObject','BNT Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201306110000','System','Net-SNMP','VlanObject','Force10 Config'),
('201306110000','System','Net-SNMP','ForwardingObject','Force10 Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201405030000','System','Net-SNMP','InventoryObject','AlliedTelesyn Config'),
('201405030000','System','Net-SNMP','Environmental','AlliedTelesyn Config'),
('201405030000','System','Net-SNMP','SwitchPortObject','AlliedTelesyn Config'),
('201405030000','System','Net-SNMP','PerformanceObject','AlliedTelesyn Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201403110000','System','Net-SNMP','ForwardingObject','HP Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201312260000','System','Net-SNMP','ForwardingObject','Aruba Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201409030000','System','Net-SNMP','PerformanceObject','FireEye Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201407170000','System','Net-SNMP','PerformanceObject','Symbol Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201409050000','System','Net-SNMP','VlanObject','Alcatel Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201411100000','System','Net-SNMP','Firewall','Fortinet Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201412010000','System','Net-SNMP','Firewall','Huawei Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201407100000','System','Net-SNMP','PerformanceObject','NEC Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201409250000','System','Net-SNMP','PerformanceObject','AcmePacket Performance'),
('201409250000','System','Net-SNMP','InventoryObject','AcmePacket Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201502030000','System','Net-SNMP','Firewall','CrossbeamSystems Config'),
('201502030000','System','Net-SNMP','InventoryObject','CrossbeamSystems Config'),
('201502030000','System','Net-SNMP','PerformanceObject','CrossbeamSystems Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201508140000','System','Net-SNMP','InventoryObject','Citrix Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201506090000','System','Net-SNMP','InventoryObject','Exinda Config'),
('201506090000','System','Net-SNMP','PerformanceObject','Exinda Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201506180000','System','Net-SNMP','InventoryObject','McAfee Config'),
('201506180000','System','Net-SNMP','PerformanceObject','McAfee Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201511170000','System','Net-SNMP','atObject','IPS ARP'),
('201511170000','System','Net-SNMP','RoutingPerfObject','IPS Routing'),
('201511170000','System','Net-SNMP','ifTableObject','IPS Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201507080000','System','Net-SNMP','VlanObject','MRV Config'),
('201507080000','System','Net-SNMP','ForwardingObject','MRV Config'),
('201507080000','System','Net-SNMP','SwitchPortObject','MRV Config'),
('201507080000','System','Net-SNMP','PerformanceObject','MRV Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201602120000','System','Net-SNMP','InventoryObject','SEL Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201603210000','System','Net-SNMP','Environmental','3Com Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201602120000','System','Net-SNMP','ForwardingObject','Arista Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201606100000','System','Net-SNMP','PerformanceObject','Citrix Load Balancer Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201602020000','System','Net-SNMP','Environmental','Fortinet Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201605260000','System','Net-SNMP','PerformanceObject','Cisco Security Manager Performance'),
('201605260000','System','Net-SNMP','atObject','Security Manager ARP'),
('201605260000','System','Net-SNMP','ipRouteTableObject','Security Manager Routing'),
('201605260000','System','Net-SNMP','RoutingInfo','Security Manager Routing'),
('201605260000','System','Net-SNMP','RoutingPerfObject','Security Manager Routing'),
('201605260000','System','Net-SNMP','ifTableObject','Security Manager Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201607210000','System','Net-SNMP','Environmental','Citrix Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201609020000','System','Net-SNMP','InventoryObject','Gigamon Config'),
('201609020000','System','Net-SNMP','Environmental','Gigamon Config'),
('201609020000','System','Net-SNMP','PerformanceObject','Gigamon Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201611080000','System','Net-SNMP','InventoryObject','Moxa Config'),
('201611080000','System','Net-SNMP','VlanObject','Moxa Config'),
('201808170000','System','Net-SNMP','ForwardingObject','Moxa Config'),
('201611080000','System','Net-SNMP','SwitchPortObject','Moxa Config'),
('201611080000','System','Net-SNMP','PerformanceObject','Moxa Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201609280000','System','Net-SNMP','Environmental','AcmePacket Config'),
('202005150000','System','Net-SNMP','ipRouteTableObject','AcmePacket Config'),
('202005150000','System','Net-SNMP','atObject','AcmePacket Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201701230000','System','Net-SNMP','ipRouteTableObject','Media Gateway Routing'),
('201701230000','System','Net-SNMP','RoutingInfo','Media Gateway Routing'),
('201701230000','System','Net-SNMP','RoutingPerfObject','Media Gateway Routing'),
('201701230000','System','Net-SNMP','InventoryObject','Media Gateway Config'),
('201701230000','System','Net-SNMP','Environmental','Media Gateway Config'),
('201701230000','System','Net-SNMP','atObject','Media Gateway ARP'),
('201701230000','System','Net-SNMP','ifTableObject','Media Gateway Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201608170000','System','Net-SNMP','ipRouteTableObject','Web Gateway Routing'),
('201608170000','System','Net-SNMP','RoutingInfo','Web Gateway Routing'),
('201608170000','System','Net-SNMP','RoutingPerfObject','Web Gateway Routing'),
('201608170000','System','Net-SNMP','ifTableObject','Web Gateway Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201604270000','System','Net-SNMP','InventoryObject','Ibmnetwork Config'),
('201604270000','System','Net-SNMP','PerformanceObject','Ibmnetwork Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201701060000','System','Net-SNMP','InventoryObject','DCN Config'),
('201701060000','System','Net-SNMP','PerformanceObject','DCN Performance'),
('201701060000','System','Net-SNMP','PerformanceObject','DCN Performance'),
('201701060000','System','Net-SNMP','PerformanceObject','DCN Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201704140000','System','Net-SNMP','InventoryObject','Opengear Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201702080000','System','Net-SNMP','InventoryObject','Raisecom Config'),
('201702080000','System','Net-SNMP','Environmental','Raisecom Config'),
('201702080000','System','Net-SNMP','SwitchPortObject','Raisecom Config'),
('201702080000','System','Net-SNMP','PerformanceObject','Raisecom Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201712070000','System','Net-SNMP','InventoryObject','D-Link Config'),
('201712070000','System','Net-SNMP','Environmental','D-Link Config'),
('201712070000','System','Net-SNMP','SwitchPortObject','D-Link Config'),
('201712070000','System','Net-SNMP','PerformanceObject','D-Link Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201805020000','System','Net-SNMP','ForwardingObject','Samsung Config'),
('201805020000','System','Net-SNMP','SwitchPortObject','Samsung Config'),
('201805020000','System','Net-SNMP','Environmental','Samsung Switch Config'),
('201805020000','System','Net-SNMP','PerformanceObject','Samsung Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201705160000','System','Net-SNMP','ForwardingObject','Nortel Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201803030000','System','Net-SNMP','InventoryObject','CumulusNetworks Config'),
('201803030000','System','Net-SNMP','Environmental','CumulusNetworks Config'),
('201803030000','System','Net-SNMP','VlanObject','CumulusNetworks Config'),
('201803030000','System','Net-SNMP','SwitchPortObject','CumulusNetworks Config'),
('201803030000','System','Net-SNMP','PerformanceObject','CumulusNetworks Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201806120000','System','Net-SNMP','InventoryObject','Spectracom Config'),
('201806120000','System','Net-SNMP','Environmental','Spectracom Config'),
('201806120000','System','Net-SNMP','atObject','Spectracom ARP'),
('201806120000','System','Net-SNMP','ipRouteTableObject','Spectracom Routing'),
('201806120000','System','Net-SNMP','ifTableObject','Spectracom Performance'),
('201806120000','System','Net-SNMP','PerformanceObject','Spectracom Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201704110000','System','Net-SNMP','ifTableObject','Emerson Performance'),
('201704110000','System','Net-SNMP','InventoryObject','Emerson Config'),
('201704110000','System','Net-SNMP','Environmental','Emerson Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201806190000','System','Net-SNMP','atObject','Storage Appliance ARP'),
('201806190000','System','Net-SNMP','ipRouteTableObject','Storage Appliance Routing'),
('201806190000','System','Net-SNMP','ifTableObject','Storage Appliance Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201806130000','System','Net-SNMP','InventoryObject','Avocent Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201803200000','System','Net-SNMP','Environmental','APCON Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201810310000','System','Net-SNMP','Environmental','ArrayNetworks Config'),
('201810310000','System','Net-SNMP','PerformanceObject','ArrayNetworks Load Balancer Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201805140000','System','Net-SNMP','Environmental','Talari Config'),
('201805140000','System','Net-SNMP','PerformanceObject','Talari SD-WAN Performance'),
('201805140000','System','Net-SNMP','atObject','SD-WAN ARP'),
('201805140000','System','Net-SNMP','ipRouteTableObject','SD-WAN Routing'),
('201805140000','System','Net-SNMP','RoutingInfo','SD-WAN Routing'),
('201805140000','System','Net-SNMP','RoutingPerfObject','SD-WAN Routing'),
('201805140000','System','Net-SNMP','ifTableObject','SD-WAN Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201805140000','System','Net-SNMP','VrfObject','Alcatel Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201809070000','System','Net-SNMP','InventoryObject','Viptela Config'),
('201809070000','System','Net-SNMP','Environmental','Viptela Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201901080000','System','Net-SNMP','InventoryObject','Ciena Config'),
('201901080000','System','Net-SNMP','Environmental','Ciena Config'),
('201901080000','System','Net-SNMP','VlanObject','Ciena Config'),
('201901080000','System','Net-SNMP','SwitchPortObject','Ciena Config'),
('201901080000','System','Net-SNMP','PerformanceObject','Ciena Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201904100000','System','Net-SNMP','InventoryObject','Meraki Config'),
('201904100000','System','Net-SNMP','VlanObject','Meraki Config'),
('201904100000','System','Net-SNMP','ForwardingObject','Meraki Config'),
('201904100000','System','Net-SNMP','SwitchPortObject','Meraki Config'),
('201904100000','System','Net-SNMP','ifTableObject','Cloud Switch Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201805030000','System','Net-SNMP','VrfObject','CheckPoint Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201902250000','System','Net-SNMP','InventoryObject','Anue Config'),
('201902250000','System','Net-SNMP','ifTableObject','NTO Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201807130000','System','Net-SNMP','atObject','Gigamon Appliance ARP'),
('201807130000','System','Net-SNMP','ipRouteTableObject','Gigamon Appliance Routing'),
('201807130000','System','Net-SNMP','RoutingInfo','Gigamon Appliance Routing'),
('201807130000','System','Net-SNMP','RoutingPerfObject','Gigamon Appliance Routing'),
('201807130000','System','Net-SNMP','ifTableObject','Gigamon Appliance Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('201907090000','System','Net-SNMP','atObject','Security-Appliance ARP'),
('201907090000','System','Net-SNMP','ipRouteTableObject','Security-Appliance Routing'),
('201907090000','System','Net-SNMP','RoutingInfo','Security-Appliance Routing'),
('201907090000','System','Net-SNMP','RoutingPerfObject','Security-Appliance Routing'),
('201907090000','System','Net-SNMP','ifTableObject','Security-Appliance Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201809140000','System','Net-SNMP','InventoryObject','ZTE Config'),
('201809140000','System','Net-SNMP','Environmental','ZTE Config'),
('201809140000','System','Net-SNMP','VlanObject','ZTE Config'),
('201809140000','System','Net-SNMP','ForwardingObject','ZTE Config'),
('201809140000','System','Net-SNMP','SwitchPortObject','ZTE Config'),
('201809140000','System','Net-SNMP','PerformanceObject','ZTE Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201904030000','System','Net-SNMP','InventoryObject','Uplogix Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201910020000','System','Net-SNMP','VlanObject','Citrix Load Balancer L2'),
('201910020000','System','Net-SNMP','SwitchPortObject','Citrix Load Balancer L2');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201904090000','System','Net-SNMP','Firewall','CheckPoint Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201809190000','System','Net-SNMP','SwitchPortObject','Transition Config'),
('201809190000','System','Net-SNMP','InventoryObject','Transition Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201910080000','System','Net-SNMP','InventoryObject','ServerTech Config'),
('201910080000','System','Net-SNMP','Environmental','ServerTech Config'),
('201910080000','System','Net-SNMP','ipRouteTableObject','PDU Routing'),
('201910080000','System','Net-SNMP','RoutingInfo','PDU Routing'),
('201910080000','System','Net-SNMP','RoutingPerfObject','PDU Routing'),
('201910080000','System','Net-SNMP','ifTableObject','PDU Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202003030000','System','Net-SNMP','InventoryObject','BSN Config'),
('202003030000','System','Net-SNMP','PerformanceObject','BSN Performance'),
('202003030000','System','Net-SNMP','Environmental','BSN Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202002020000','System','Net-SNMP','ipRouteTableObject','APC Routing'),
('202002020000','System','Net-SNMP','RoutingInfo','APC Routing'),
('202002020000','System','Net-SNMP','RoutingPerfObject','APC Routing'),
('202002020000','System','Net-SNMP','atObject','APC ARP'),
('202002020000','System','Net-SNMP','ifTableObject','APC Performance'),
('202002020000','System','Net-SNMP','InventoryObject','APC Config'),
('202002020000','System','Net-SNMP','Environmental','APC Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202003310000','System','Net-SNMP','InventoryObject','Cisco Server Config'),
('202003310000','System','Net-SNMP','Environmental','Cisco Server Config'),
('202003310000','System','Net-SNMP','atObject','Server ARP'),
('202003310000','System','Net-SNMP','ipRouteTableObject','Server Routing'),
('202003310000','System','Net-SNMP','RoutingInfo','Server Routing'),
('202003310000','System','Net-SNMP','RoutingPerfObject','Server Routing'),
('202003310000','System','Net-SNMP','ifTableObject','Server Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('201906260000','System','Net-SNMP','ifTableObject','Cloud AP Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202009110000','System','Net-SNMP','atObject','Service Delivery Platform ARP'),
('202009110000','System','Net-SNMP','ipRouteTableObject','Service Delivery Platform Routing'),
('202009110000','System','Net-SNMP','RoutingInfo','Service Delivery Platform Routing'),
('202009110000','System','Net-SNMP','RoutingPerfObject','Service Delivery Platform Routing'),
('202009110000','System','Net-SNMP','ifTableObject','Service Delivery Platform Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202009010000','System','Net-SNMP','atObject','Infinera ARP'),
('202009010000','System','Net-SNMP','ipRouteTableObject','Infinera Routing'),
('202009010000','System','Net-SNMP','RoutingInfo','Infinera Routing'),
('202009010000','System','Net-SNMP','RoutingPerfObject','Infinera Routing'),
('202009010000','System','Net-SNMP','InventoryObject','Infinera Config'),
('202009010000','System','Net-SNMP','Environmental','Infinera Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202010020000','System','Net-SNMP','InventoryObject','Ubiquiti Config'),
('202010020000','System','Net-SNMP','ipRouteTableObject','Ubiquiti Routing'),
('202010020000','System','Net-SNMP','PerformanceObject','Ubiquiti Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('202004130000','System','Net-SNMP','VlanObject','Alteon Config'),
('202004130000','System','Net-SNMP','SwitchPortObject','Alteon Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202006080000','System','Net-SNMP','InventoryObject','Coriant Config'),
('202006080000','System','Net-SNMP','Environmental','Coriant Config'),
('202006080000','System','Net-SNMP','ifTableObject','Coriant Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202102190000','System','Net-SNMP','InventoryObject','SilverPeak Config'),
('202102190000','System','Net-SNMP','PerformanceObject','SilverPeak Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202103190000','System','Net-SNMP','ipRouteTableObject','F5 Routing'),
('202103190000','System','Net-SNMP','InventoryObject','F5 Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202008250000','System','Net-SNMP','Environmental','Riverbed Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202105030000','System','Net-SNMP','Environmental','Avocent Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202104140000','System','Net-SNMP','InventoryObject','Alaxala Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202105180000','System','Net-SNMP','VrfObject','PaloAltoNetworks Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202108110000','System','Net-SNMP','Firewall','StormShield Config'),
('202108110000','System','Net-SNMP','InventoryObject','StormShield Config'),
('202108110000','System','Net-SNMP','Environmental','StormShield Config'),
('202108110000','System','Net-SNMP','PerformanceObject','StormShield Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202108170000','System','Net-SNMP','InventoryObject','Pulse Secure Config'),
('202108170000','System','Net-SNMP','Environmental','Pulse Secure Config'),
('202108170000','System','Net-SNMP','PerformanceObject','Pulse Secure Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202109270000','System','Net-SNMP','InventoryObject','Cloudgenix Config'),
('202109270000','System','Net-SNMP','PerformanceObject','Cloudgenix SD-WAN Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202108100000','System','Net-SNMP','InventoryObject','Riverbed Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202106140000','System','Net-SNMP','InventoryObject','Furukawa Config'),
('202106140000','System','Net-SNMP','Environmental','Furukawa Config'),
('202106140000','System','Net-SNMP','PerformanceObject','Furukawa Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202109290000','System','Net-SNMP','Environmental','Brocade Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202112200000','System','Net-SNMP','VlanObject','A10 Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202108130000','System','Net-SNMP','VrfObject','Huawei Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202107200000','System','Net-SNMP','PerformanceObject','Viptela Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202009070000','System','Net-SNMP','VrfObject','Fokus Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values
('202109010000','System','Net-SNMP','InventoryObject','Raritan Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202109220000','System','Net-SNMP','InventoryObject','Mellanox Config'),
('202109220000','System','Net-SNMP','Environmental','Mellanox Config'),
('202109220000','System','Net-SNMP','VlanObject','Mellanox Config'),
('202109220000','System','Net-SNMP','ForwardingObject','Mellanox Config'),
('202109220000','System','Net-SNMP','SwitchPortObject','Mellanox Config'),
('202109220000','System','Net-SNMP','PerformanceObject','Mellanox Performance'),
('202109220000','System','Net-SNMP','PerformanceObject','Mellanox Performance');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202112160000','System','Net-SNMP','VrfObject','H3C Config');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202301040000','System','Net-SNMP','InventoryObject','Eaton UPS Config'),
('202301040000','System','Net-SNMP','Environmental','Eaton UPS Config');
replace into PropertyGroupDef
(PropertyGroup,dsb,Source,PropertyName,version) values 
('Cisco Security Manager Config','System','Net-SNMP','Environmental','202407230000');
replace into PropertyGroupDef
(Source,PropertyGroup,dsb,version,PropertyName) values 
('Net-SNMP','CheckPoint Config','System','202410150000','InventoryObject');
replace into PropertyGroupDef
(PropertyName,dsb,version,Source,PropertyGroup) values 
('InventoryObject','System','202502030000','Net-SNMP','Extreme Config');
replace into PropertyGroupDef
(Source,PropertyGroup,PropertyName,dsb,version) values 
('Net-SNMP','HP Config','VrfObject','System','202407190000');
replace into PropertyGroupDef
(Source,PropertyName,PropertyGroup,dsb,version) values 
('Net-SNMP','Environmental','Extreme Config','System','202402010000'),
('Net-SNMP','ForwardingObject','Extreme Config','System','202402010000');
replace into PropertyGroupDef
(version,PropertyGroup,dsb,PropertyName,Source) values 
('202306040000','Alcatel Config','System','VrfObject','Net-SNMP');
replace into PropertyGroupDef
(Source,version,PropertyName,PropertyGroup,dsb) values 
('Net-SNMP','202306150000','VrfObject','HP Config','System');
replace into PropertyGroupDef
(PropertyGroup,Source,version,PropertyName,dsb) values 
('Cisco Config','Net-SNMP','202411250000','Environmental','System'),
('Cisco Config','Net-SNMP','202404070000','InventoryObject','System'),
('Cisco Config','Net-SNMP','202503140000','ForwardingObject','System');
replace into PropertyGroupDef
(Source,dsb,version,PropertyGroup,PropertyName) values 
('Net-SNMP','System','202203030000','Raisecom Config','InventoryObject');
replace into PropertyGroupDef
(version,dsb,Source,PropertyGroup,PropertyName) values 
('202201240000','System','Net-SNMP','Extreme Performance','PerformanceObject');
replace into PropertyGroupDef
(Source,PropertyGroup,dsb,version,PropertyName) values 
('Net-SNMP','Huawei Config','System','202207010000','ForwardingObject');
replace into PropertyGroupDef
(PropertyGroup,Source,dsb,PropertyName,version) values 
('Dionis Config','Net-SNMP','System','InventoryObject','202301240000');
replace into PropertyGroupDef
(Source,PropertyGroup,dsb,PropertyName,version) values 
('Net-SNMP','Netgear Config','System','InventoryObject','202405050000'),
('Net-SNMP','Netgear Config','System','VlanObject','202405050000'),
('Net-SNMP','Netgear Config','System','ForwardingObject','202405050000'),
('Net-SNMP','Netgear Config','System','SwitchPortObject','202405050000');
replace into PropertyGroupDef
(PropertyName,PropertyGroup,dsb,version,Source) values 
('PerformanceObject','LavelleNetworks Performance','System','202405090000','Net-SNMP'),
('PerformanceObject','LavelleNetworks Performance','System','202405090000','Net-SNMP');
replace into PropertyGroupDef
(PropertyName,version,dsb,Source,PropertyGroup) values 
('InventoryObject','202410300000','System','Net-SNMP','Versa Config');
replace into PropertyGroupDef
(PropertyGroup,PropertyName,version,dsb,Source) values 
('Versa Config','VrfObject','202410080000','System','Net-SNMP');
replace into PropertyGroupDef
(version,PropertyName,dsb,Source,PropertyGroup) values 
('202405200000','InventoryObject','System','Net-SNMP','VMWare Config');
replace into PropertyGroupDef
(PropertyName,version,dsb,PropertyGroup,Source) values 
('VrfObject','202402260000','System','Nortel Config','Net-SNMP');
replace into PropertyGroupDef
(version,PropertyGroup,dsb,Source,PropertyName) values 
('202302220000','HP Wireless AP Config','System','Net-SNMP','InventoryObject');
replace into PropertyGroupDef
(version,dsb,Source,PropertyName,PropertyGroup) values 
('202505120000','System','Net-SNMP','VrfObject','Extreme Config');
replace into PropertyGroupDef
(version,Source,dsb,PropertyName,PropertyGroup) values 
('202506100000','Net-SNMP','System','InventoryObject','PaloAltoNetworks Config');
replace into PropertyGroupDef
(dsb,PropertyName,version,Source,PropertyGroup) values 
('System','InventoryObject','202504020000','Net-SNMP','Tejas Config'),
('System','Environmental','202504020000','Net-SNMP','Tejas Config'),
('System','VlanObject','202504020000','Net-SNMP','Tejas Config'),
('System','ForwardingObject','202504020000','Net-SNMP','Tejas Config'),
('System','SwitchPortObject','202504020000','Net-SNMP','Tejas Config'),
('System','PerformanceObject','202504020000','Net-SNMP','Tejas Performance');
replace into PropertyGroupDef
(PropertyGroup,PropertyName,Source,version,dsb) values 
('Cisco Cloud-Hypervisor Performance','PerformanceObject','Net-SNMP','202304060000','System');
replace into PropertyGroupDef
(Source,PropertyGroup,PropertyName,version,dsb) values 
('Net-SNMP','ZPE Console Server Config','Environmental','202307240000','System'),
('Net-SNMP','ZPE Performance','PerformanceObject','202307240000','System');
