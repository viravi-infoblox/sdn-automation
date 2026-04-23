use netmri;

drop table if exists VeloCloudOrganization;

create table VeloCloudOrganization (
    id          char(64) not null,
    name        char(255),
    fabric_id   int unsigned not null,
	StartTime			DATETIME	not null,
	EndTime				DATETIME	not null,
    constraint MerakiOrganization_PK primary key (id, fabric_id)
) ENGINE=InnoDB;

replace netmri.VersionControl (Type, Name, Version, Timestamp)
values ("table", "netmri.VeloCloudOrganization", "1", now());
