# Mojo::Discord

A Perl wrapper for the Discord API, intended for use primarily with text-based chat bots.

This library was created to facilitate my own Discord Bot, [Goose](https://github.com/vsterminus/Goose).

## Modules

The primary modules involved are:

- **Mojo::Discord** - A top level wrapper and single point of entry for all other modules
- **Mojo::Discord::Auth** - OAuth 2 implementation (largely incomplete)
- **Mojo::Discord::REST** - REST API wrapper
- **Mojo::Discord::Gateway** - Discord Websocket client implementation
- **Mojo::Discord::User** - Discord User object, stores properties about users
- **Mojo::Discord::Guild** - Manage all properties related to guilds (Servers)

Below Mojo::Discord::Guild are smaller modules for various guild items such as channels, emoji, and roles.

## Note: This is a spare-time project

Best intentions laid bare I have a lot of projects on the go and this one does not always receive the attention it deserves.

I have not abandoned the project nor do I have any intent to, but when my own needs are met (eg, Goose Bot is working) work on this library often stops.

You are welcome to submit pull requests if you want to build support parts of the API that I have not covered. The API is quite large and there are many aspects of it I have no plans to use and may not ever implement here myself (eg, Voice).

## Pre-Requisites

- **Mojo::UserAgent**  and **Mojo::IOLoop** to provide non-blocking asynchronous HTTP calls and websocket functionality.
- **Mojo::UserAgent::Role::Queued** provides connection and rate limiting support for Mojo::UserAgent.
- **Compress::Zlib**, as some of the incoming messages are compressed Zlib blobs
- **Mojo::JSON** to convert the compressed JSON messages into Perl structures.
- **Mojo::Util** to handle base64 avatar data conversion.
- **Mojo::Log** for the library to log events to disk.
- **JSON::MaybeXS** for proper escaping of unicode characters so discord will encode them correctly.
- **Encode::Guess** to determine whether we're dealing with a compressed stream or not.
- **Data::Dumper** to debug complex objects.
- **IO::Socket::SSL** to fetch the Websocket URL for Discord to connect to.
- **Role::EventEmitter** to replace callbacks and allow client applications to subscribe to various Discord events.
- **URI::Escape** to pass Unicode to the REST API endpoints, eg emojis.
- **Time::Duration** to calculation durations between timestamps, eg for connection uptime.

These dependencies can be installed using cpanminus with the following command in the project root:
    
    cpanm --installdeps .


## Mojo::Discord::Gateway

The Discord "Gateway" is a persistent Websocket connection that sends out events as they happen to all connected clients.
This module monitors the gateway and parses all of the events it dispatches. The library stores information from some of these events to help it function and offer certain capabilities, but many of the events are simply re-emitted (Role::EventEmitter) to the client for it to use that information how it pleases. Clients can subscribe to these events if they wish to receive them.

The connection process goes a little like this:

1. Request a Gateway URL to connect to
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

use Mojo::Discord;
use Data::Dumper;

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
