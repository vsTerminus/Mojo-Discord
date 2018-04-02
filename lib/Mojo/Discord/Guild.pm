package Mojo::Discord::Guild;

use Moo;
use strictures 2;

use Mojo::Discord::Guild::Member;
use Mojo::Discord::Guild::Role;
use Mojo::Discord::Guild::Channel;
use Mojo::Discord::Guild::Emoji;
use Mojo::Discord::Guild::Presence;
use Data::Dumper;

has id                              => ( is => 'rw' );
has members                         => ( is => 'rw' );
has roles                           => ( is => 'rw' );
has channels                        => ( is => 'rw' );
has webhooks                        => ( is => 'rw' );
has owner_id                        => ( is => 'rw' );
has name                            => ( is => 'rw' );
has splash                          => ( is => 'rw' );
has features                        => ( is => 'rw' );
has joined_at                       => ( is => 'rw' );
has icon                            => ( is => 'rw' );
has presences                       => ( is => 'rw' );
has voice_states                    => ( is => 'rw' );
has region                          => ( is => 'rw' );
has application_id                  => ( is => 'rw' );
has unavailable                     => ( is => 'rw' );
has member_count                    => ( is => 'rw' );
has afk_channel_id                  => ( is => 'rw' );
has default_message_notifications   => ( is => 'rw' );
has large                           => ( is => 'rw' );
has emojis                          => ( is => 'rw' );
has afk_timeout                     => ( is => 'rw' );
has verification_level              => ( is => 'rw' );
has mfa_level                       => ( is => 'rw' );

__PACKAGE__->meta->make_immutable;

1;
