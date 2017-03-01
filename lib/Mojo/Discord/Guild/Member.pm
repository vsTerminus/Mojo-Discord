package Mojo::Discord::Guild::Member;

use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(id username discriminator avatar mute roles deaf nick joined_at);

has ['id', 'username', 'discriminator', 'avatar', 'mute', 'roles', 'deaf', 'nick', 'joined_at'];

1;
