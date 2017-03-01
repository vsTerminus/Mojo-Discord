package Mojo::Discord::Guild::Presence;

use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(id game user status);

has ['id', 'game', 'user', 'status'];

1;
