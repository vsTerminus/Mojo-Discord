package Mojo::Discord::Guild::Emoji;

use Moo;
use strictures 2;

extends 'Mojo::Discord::Guild';

has id              => ( is => 'rw' );
has name            => ( is => 'rw' );
has require_colons  => ( is => 'rw' );
has managed         => ( is => 'rw' );
has roles           => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
