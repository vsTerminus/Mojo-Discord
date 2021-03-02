package Mojo::Discord::Guild;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

use Mojo::Discord::Guild::Member;
use Mojo::Discord::Guild::Role;
use Mojo::Discord::Guild::Channel;
use Mojo::Discord::Guild::Emoji;
use Mojo::Discord::Guild::Presence;

use namespace::clean;

has id                              => ( is => 'rw' );
has members                         => ( is => 'rw', default => sub { {} } );
has roles                           => ( is => 'rw', default => sub { {} } );
has channels                        => ( is => 'rw', default => sub { {} } );
has webhooks                        => ( is => 'rw', default => sub { {} } );
has emojis                          => ( is => 'rw', default => sub { {} } );
has presences                       => ( is => 'rw', default => sub { {} } );
has owner_id                        => ( is => 'rw' );
has name                            => ( is => 'rw' );
has splash                          => ( is => 'rw' );
has features                        => ( is => 'rw' );
has joined_at                       => ( is => 'rw' );
has icon                            => ( is => 'rw' );
has voice_states                    => ( is => 'rw' );
has region                          => ( is => 'rw' );
has application_id                  => ( is => 'rw' );
has unavailable                     => ( is => 'rw' );
has member_count                    => ( is => 'rw' );
has afk_channel_id                  => ( is => 'rw' );
has default_message_notifications   => ( is => 'rw' );
has large                           => ( is => 'rw' );
has afk_timeout                     => ( is => 'rw' );
has verification_level              => ( is => 'rw' );
has mfa_level                       => ( is => 'rw' );

# Pass in a hash of top level attributes
sub set_attributes
{
    my ($self, $hash) = @_;

    # List of attributes it is possible to find at the top level
    # of a guild object.
    # This acts as a sort of whitelist so that complex structures like channels
    # cannot be added this way.
    my @attrs = (
        'id',
        'name',
        'icon',
        'splash',
        'owner',
        'owner_id',
        'region',
        'afk_channel_id',
        'afk_timeout',
        'embed_enabled',
        'embed_channel_id',
        'verification_level',
        'default_message_notifications',
        'explicit_content_filter',
        'mfa_level',
        'application_id',
        'widget_enabled',
        'widget_channel_id',
        'system_channel_id',
        'joined_at',
        'large',
        'unavailable',
        'member_count',
    );

    foreach my $attr (@attrs)
    {
        if ( exists $hash->{$attr} )
        {
            $self->{$attr} = $hash->{$attr};
        }
    }
}

# Need functions to add, remove, and edit things as they change.
sub add_channel
{
    my ($self, $args) = @_;

#    print Dumper($args);

    my $id = $args->{'id'};
    die("Cannot add a channel without an id.\nDied ") unless defined $id;

    # Add the guild ID to the object
    $args->{'guild_id'} = $self->id;

    my $channel = Mojo::Discord::Guild::Channel->new($args);
    $self->channels->{$id} = $channel;

    #print Dumper($self->channels);

    # Return the new object
    return $channel;
}

sub remove_channel
{
    my ($self, $channel_id) = @_;

    delete $self->channels->{$channel_id};
}

sub add_role
{
    my ($self, $args) = @_;

    my $id = $args->{'id'};
    die("Cannot add a role without an id.\nDied ") unless defined $id;

    my $role = Mojo::Discord::Guild::Role->new($args);

    $self->roles->{$id} = $role;

    return $role;
}

sub remove_role
{
    my ($self, $role_id) = @_;

    delete $self->roles->{$role_id};
}

sub add_presence
{
    my ($self, $args) = @_;

    my $id = $args->{'id'};
    die("Cannot add a presence without an id.\nDied ") unless defined $id;

    my $presence = Mojo::Discord::Guild::Presence->new($args);

    $self->presences->{$id} = $presence;

    return $presence;
}

sub remove_presence
{
#    my ($self, $presence_id) = @_;

#    delete $self->presences{$presence_id};
}

sub add_emoji
{
    my ($self, $args) = @_;

    my $id = $args->{'id'};
    die("Cannot add an emoji without an id.\nDied ") unless defined $id;

    my $emoji = Mojo::Discord::Guild::Emoji->new($args);

    $self->emojis->{$id} = $emoji;

    return $emoji;
}

sub remove_emoji
{
#    my ($self, $emoji_id) = @_;

#    delete $self->emoji{$emoji_id};
}

sub add_member
{
    my ($self, $args) = @_;

    my $id = $args->{'user'}{'id'};
    die("Cannot add a member without an id.\nDied ") unless defined $id;

    my $member = Mojo::Discord::Guild::Member->new($args);

    $self->members->{$id} = $member;

    return $member;
}

sub remove_member
{
    my ($self, $member_id) = @_;

    delete $self->members->{$member_id};
}

1;
