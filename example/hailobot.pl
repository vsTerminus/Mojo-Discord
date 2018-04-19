#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Hailo;
use Mojo::Discord;
use Config::Tiny;
use Mojo::IOLoop;

# Fallback to "config.ini" if the user does not pass in a config file.
my $config_file = $ARGV[0] // 'config.ini';
my $config = Config::Tiny->read($config_file, 'utf8');
say localtime(time) . " - Loaded Config: $config_file";

# Create the Hailo Object
my $brain = $config->{'hailo'}->{'brain_file'};
my $hailo = Hailo->new({'brain' => $brain});

my $discord;
my $discord_name;
my $discord_id;

$discord = Mojo::Discord->new(
    'token'     => $config->{'discord'}->{'token'},
    'name'      => $config->{'discord'}->{'name'},
    'url'       => $config->{'discord'}->{'redirect_url'},
    'version'   => '1.0',
    'callbacks' => {
        'READY'          => \&discord_on_ready,
        'MESSAGE_CREATE' => \&discord_on_message_create,
    },
    'reconnect' => $config->{'discord'}->{'auto_reconnect'},
    'verbose'   => $config->{'discord'}->{'verbose'},
);

sub discord_on_ready
{
    my ($hash) = @_;

    $discord_name   = $hash->{'user'}{'username'};
    $discord_id     = $hash->{'user'}{'id'};

    say localtime(time) . " - Connected to Discord.";
};

sub discord_on_message_create
{
    my $hash = shift;

    my $author = $hash->{'author'};
    my $msg = $hash->{'content'};
    my $channel = $hash->{'channel_id'};
    my @mentions = @{$hash->{'mentions'}};

    return if $author->{'id'} eq $discord_id; # Ignore my own messages
    
    foreach my $mention (@mentions)
    {
        my $id = $mention->{'id'};
        my $username = $mention->{'username'};
    
        # Replace the mention IDs in the message body with the usernames.
        $msg =~ s/\<\@\!?$id\>/$username/;
    }

    # Reply if we were mentioned
    if ( $msg =~ /^\<\@\!?$discord_id\>.? ?(.*)$/i or $msg =~ /^$config->{'discord'}{'name'}.? ?(.*)$/i ) 
    {
        my $replyto = $1;
        my $reply = $hailo->reply($replyto);    # Sometimes this takes a while.
        say "Reply=$reply";
        $discord->send_message( $channel, $reply ); # Send the response.
    }
    else # Just learn from what was said.
    {
        $hailo->learn($msg);
    }

}

$discord->init();

# Start the IOLoop unless it is already running. 
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
