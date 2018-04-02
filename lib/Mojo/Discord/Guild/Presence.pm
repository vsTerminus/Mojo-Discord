package Mojo::Discord::Guild::Presence;

use Moo;
use strictures 2;

extents 'Mojo::Discord::Guild';

has id      => ( is => 'rw' );
has game    => ( is => 'rw' );
has user    => ( is => 'rw' );
has status  => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
