package Mojo::Discord::Guild::Member;

use Moo;
use strictures 2;

extends 'Mojo::Discord::Guild';

has id              => ( is => 'rw' );
has username        => ( is => 'rw' );
has discriminator   => ( is => 'rw' );
has avatar          => ( is => 'rw' );
has mute            => ( is => 'rw' );
has roles           => ( is => 'rw' );
has deaf            => ( is => 'rw' );
has nick            => ( is => 'rw' );
has joined_at       => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
