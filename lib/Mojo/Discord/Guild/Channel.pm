package Mojo::Discord::Guild::Channel;

use Moo;
use strictures 2;

extends 'Mojo::Discord::Guild';

has id                      => ( is => 'rw' );
has last_message_id         => ( is => 'rw' );
has position                => ( is => 'rw' );
has permission_overwrites   => ( is => 'rw' );
has topic                   => ( is => 'rw' );
has type                    => ( is => 'rw' );
has name                    => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
