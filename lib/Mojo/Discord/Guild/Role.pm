package Mojo::Discord::Guild::Role;

use Moo;
use strictures 2;

extends 'Mojo::Discord::Guild';

has id              => ( is => 'rw' );
has managed         => ( is => 'rw' );
has mentionable     => ( is => 'rw' );
has permissions     => ( is => 'rw' );
has name            => ( is => 'rw' );
has position        => ( is => 'rw' );
has hoist           => ( is => 'rw' );
has color           => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
