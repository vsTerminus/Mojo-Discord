package Mojo::Discord::Guild::Emoji;
our $VERSION = '0.001';

use Moo;
use strictures 2;

has id              => ( is => 'rw' );
has name            => ( is => 'rw' );
has require_colons  => ( is => 'rw' );
has managed         => ( is => 'rw' );
has roles           => ( is => 'rw' );
has animated        => ( is => 'rw' );

1;
