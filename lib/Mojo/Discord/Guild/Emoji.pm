package Mojo::Discord::Guild::Emoji;

use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(id name require_colons managed roles);

has ['id', 'name', 'require_colons', 'managed', 'roles'];

1;
