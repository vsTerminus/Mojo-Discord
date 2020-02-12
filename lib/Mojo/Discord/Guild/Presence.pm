package Mojo::Discord::Guild::Presence;
our $VERSION = '0.001';

use Moo;
use strictures 2;

has id      => ( is => 'rw' ); # ID will be the user id.
has game    => ( is => 'rw' );
has status  => ( is => 'rw' );

1;
