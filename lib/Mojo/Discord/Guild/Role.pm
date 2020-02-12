package Mojo::Discord::Guild::Role;
our $VERSION = '0.001';

use Moo;
use strictures 2;

has id              => ( is => 'rw' );
has managed         => ( is => 'rw' );
has mentionable     => ( is => 'rw' );
has permissions     => ( is => 'rw' );
has name            => ( is => 'rw' );
has position        => ( is => 'rw' );
has hoist           => ( is => 'rw' );
has color           => ( is => 'rw' );

1;
