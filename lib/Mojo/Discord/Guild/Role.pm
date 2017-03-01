package Mojo::Discord::Guild::Role;

use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(id managed mentionable permissions name position hoist color);

has ['id', 'managed', 'mentionable', 'permissions', 'name', 'position', 'hoist', 'color'];

1;
