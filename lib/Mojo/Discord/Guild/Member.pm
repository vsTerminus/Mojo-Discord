package Mojo::Discord::Guild::Member;
our $VERSION = '0.001';

use Moo;
use strictures 2;

has id              => ( is => 'rw' );
has nick            => ( is => 'rw' );
has mute            => ( is => 'rw' );
has roles           => ( is => 'rw' );
has deaf            => ( is => 'rw' );
has joined_at       => ( is => 'rw' );

1;
