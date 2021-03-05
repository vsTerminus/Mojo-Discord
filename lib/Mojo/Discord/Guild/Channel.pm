package Mojo::Discord::Guild::Channel;
our $VERSION = '0.001';

use Moo;
use strictures 2;

has id                      => ( is => 'rw' );
has guild_id                => ( is => 'rw' );
has last_message_id         => ( is => 'rw' );
has position                => ( is => 'rw' );
has permission_overwrites   => ( is => 'rw' );
has topic                   => ( is => 'rw' );
has type                    => ( is => 'rw' );
has name                    => ( is => 'rw' );

1;
