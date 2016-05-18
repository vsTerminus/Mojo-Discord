# Net-Discord

This is a set of Perl Modules designed to implement parts of the Discord public API.
It is intended for users wishing to create some variety of text-chat bots.

There are three modules involved

- **Net::Discord::Gateway** handles the Websocket realtime event monitoring part (connect and monitor the chat)
- **Net::Discord::REST** handles calls to the REST web API for things you want the bot to actualy *do* (eg, send a message)
- **Net::Discord** is a wrapper that saves the user the trouble of managing both APIs manually.

## Note: This module does not and likely will never implement the complete API.

This is a spare-time project, which means I will likely implement only what I need in order for my bots to function.
I will most likely cover most text based events, but will almost certainly never implement anything for voice.

In addition, the error handling and reconnect will likely not be very robust. Again, this is not intended to be a complete implementation.

If you want to contribute, feel free to fork the repository and send me a pull request. If not, that's OK too.

## Pre-Requisites

**Net::Discord** heavily utilizes **Mojo::UserAgent** and **Mojo::IOLoop** to provide non-blocking asynchronous HTTP calls and websocket functionality.
You'll also need **Compress::Zlib**, as some of the incoming messages are compressed Zlib blobs, and **Mojo::JSON** to convert the JSON messages into Perl structures.

## Example Program

This application creates a very basic AI Chat Bot using the Hailo module (a modern implementation of MegaHAL)

```perl
#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Net::Discord;
use Hailo;

# Hailo vars
my $hailo_brain = 'brain.sqlite';
my $hailo = Hailo->new({'brain' => $hailo_brain});

# Discord vars
my $discord_token = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxx';    # This will be supplied to you in the Discord Developers section when you create a new bot user.
my $discord_name = 'ChatBot9000';   # Username for chat.
my $discord_url = 'https://localhost'; # Doesn't really matter what this URL is, it just has to be there, and it's supposed to match what you configure in your Discord application.
my $discord_version = '0.1';    # Version of your application. Doesn't matter, it's just for your UserAgent string.
my $discord_callbacks = {       # Tell Discord what functions to call for event callbacks. It's not POE, but it works.
    'on_ready'          => \&on_ready,
    'on_message_create' => \&on_message_create
};
my %self;   # We'll store some information about ourselves here from the Discord API

# Create a new Net::Discord object, passing in the token, application name/url/version, and your callback functions as a hashref
my $discord = Net::Discord->new(
        {
            'token' => $discord_token,
            'name' => $discord_name,
            'url' => $discord_url,
            'version' => $discord_version,
            'callbacks' => $discord_callbacks
        });
        
# Callback for on_ready event, which contains a bunch of useful information
# We're only going to capture our username and user id for now, but there is a lot of other info in this structure.
sub on_ready
{
    my ($hash) = @_;

    $self{'username'} = $hash->{'user'}{'username'};
    $self{'id'} = $hash->{'user'}{'id'};

    $discord->status_update({'game' => 'Hailo'});
};

# "MESSAGE_CREATE" is the event generated when someone sends a text chat to a channel.
# We'll capture some info about the author, the message contents, and the list of @mentions so we can see if we need to respond to something.
# The incoming structure uses User IDs instead of Names in the content, so we'll swap those around so Hailo can generate a meaningful reply.
# Finally, if we were mentioned at the start of the line, we'll have Hailo generate a reply to the text and send it back to the channel.
sub on_message_create
{
    my $hash = shift;

    # Store a few things from the hash structure
    my $author = $hash->{'author'};
    my $msg = $hash->{'content'};
    my $channel = $hash->{'channel_id'};
    my @mentions = @{$hash->{'mentions'}};

    # Loop through the list of mentions and replace User IDs with Usernames.
    foreach my $mention (@mentions)
    {
        my $id = $mention->{'id'};
        my $username = $mention->{'username'};

        # Replace the mention IDs in the message body with the usernames.
        $msg =~ s/\<\@$id\>/$username/;
    }

    # If we were mentioned, generate a reply
    if ( $msg =~ /^$self{'username'}/i )
    {
        $msg =~ s/^$self{'username'}.? ?//i;   # Remove the username. Can I do this as part of the if statement?

        $discord->start_typing($channel); # Tell the channel we're thinking about a response
        my $reply = $hailo->reply($msg);    # Sometimes this takes a while.
        $discord->send_message( $channel, $reply ); # Send the response.
    }

}

# Establish the web socket connection and start the listener
# This should be the last line, as nothing below it will be executed.
$discord->connect();

```

## Net::Discord::Gateway

The Discord "Gateway" is a persistent Websocket connection that sends out events as they happen to all connected clients.
This module monitors the gateway and parses events, although once connected it largely reverts to simply passing the contents of each message to the appropriate callback function, as defined by the user.

The connection process goes a little like this:

1. Request a Gateway URL to connect to
    a. Seems to always return the same URL now, but in the past it looks like they had multiple URLs and servers.
2. Open a websocket connection to the URL received in Step 1.
3. Once connected, send an IDENTIFY message to the server containing info about who we are (Application-wise)
4. Gateway sends us a READY message containing (potentially) a ton of information about our user identity, the servers we are connected to, a heartbeat interval, and so on.
5. Use the Heartbeat Interval supplied in Step 4 to send a HEARTBEAT message to the server periodically. This lets the server know we are still there, and it will close our connection if we do not send it.

Now that we're connected and sending a heartbeat, all we have to do is listen for incoming messages and pass them off to the correct handler and callback functions.

## Net::Discord::REST

The REST module exists for when you want your bot to take some kind of action. It's a fairly simple JSON API, you just need to include your bot token in the header for calls.

This module will implement calls for sending messages, indicating the user has started typing, and maybe a few other things that a text chat bot needs to be able to do.
