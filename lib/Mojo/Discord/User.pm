package Mojo::Discord::User;
our $VERSION = '0.001';

use Moo;
use strictures 2;

# Store information about discord users
has id              => ( is => 'rw' );
has username        => ( is => 'rw' );
has nick            => ( is => 'rw' );
has discriminator   => ( is => 'rw' );
has avatar          => ( is => 'rw' );

1;
