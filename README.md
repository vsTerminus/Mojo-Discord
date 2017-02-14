# Mojo::Discord

This is a set of Perl Modules designed to implement parts of the Discord public API, build on Mojo::IOLoop.

There are four modules involved

- **Mojo::Discord::Auth** handles OAuth2
- **Mojo::Discord::Gateway** handles the Websocket realtime event monitoring part (connect and monitor the chat)
- **Mojo::Discord::REST** handles calls to the REST web API, which mostly handles actions you want the bot to take
- **Mojo::Discord** is a wrapper that saves the user the trouble of managing both REST and Gateway APIs manually.

## Note: This is a spare-time project

I offer no promises as to code completion, timeline, or even support. If you have questions I will try to answer.


## Second Note: Amateur code warning

I would recommend not building anything on this code for now. It is lacking in documentation, error handling, and other things.
I hope to improve this over time, but again because it's a side project I can only do so much with the time I have.

## Pre-Requisites

- **Mojo::UserAgent**  and **Mojo::IOLoop** to provide non-blocking asynchronous HTTP calls and websocket functionality.
- **Compress::Zlib**, as some of the incoming messages are compressed Zlib blobs
- **Mojo::JSON** to convert the compressed JSON messages into Perl structures.
- **Encode::Guess** to determine whether we're dealing with a compressed stream or not

### Example Program

This application creates a very basic AI Chat Bot using the Hailo module (a modern implementation of MegaHAL)

```perl
#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Mojo::Discord;
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

# Create a new Mojo::Discord object, passing in the token, application name/url/version, and your callback functions as a hashref
my $discord = Mojo::Discord->new(
        {
            'token' => $discord_token,
            'name' => $discord_name,
            'url' => $discord_url,
            'version' => $discord_version,
            'callbacks' => $discord_callbacks,
            'verbose'   => 1
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

## Mojo::Discord::Gateway

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

## Mojo::Discord::REST

The REST module exists for when you want your bot to take some kind of action. It's a fairly simple JSON API, you just need to include your bot token in the header for calls.

This module will implement calls for sending messages, indicating the user has started typing, and maybe a few other things that a text chat bot needs to be able to do.

## Mojo::Discord::Auth

This module was created to implement parts of the OAuth2 authentication method for Discord.
It is far from complete and still requires some copy/pasting, but it functions.
Since OAuth is not required for bot clients, this module may not be included in the Mojo::Discord wrapper.
Using it directly might make more sense.

Creating a new Mojo::Discord::Auth object takes the same arguments as above, but also requires an Application ID, Shared Secret, and the Auth Code received from the browser.

The only function implemented so far is request_token, which sends the auth code to the token endpoint and returns 
- Access Token
- Refresh Token
- Expiration Time
- Token Type
- Access Scope

### Example Code:

```perl

#!/usr/bin/env perl

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use Mojo::Discord::Auth;
use Data::Dumper

my $params = {
    'name' => 'Your Application Name',
    'url' => 'https://yourwebsite.com',
    'version' => '0.1',
    'code'  => $ARGV[0],
    'id'    => 'your_application_id',
    'secret' => 'your_application_secret',
};

my $auth = Mojo::Discord::Auth->new($params);

my $token_hash = $auth->request_token();

# Do something with the result
print Dumper($token_hash);
```
