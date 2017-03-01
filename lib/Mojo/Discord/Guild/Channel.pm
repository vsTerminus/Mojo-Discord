package Mojo::Discord::Guild::Channel;

use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(id last_message_id position permission_overwrites topic type name);

has ['id', 'last_message_id', 'position', 'permission_overwrites', 'topic', 'type', 'name'];

1;
