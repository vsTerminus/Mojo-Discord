package Mojo::Discord::Guild::Presence;

use Moo;
use strictures 2;

has id      => ( is => 'rw' ); # ID will be the user id.
has game    => ( is => 'rw' );
has status  => ( is => 'rw' );

1;
