# To use: cpanm --installdeps .
requires 'Moo';                             # OO Framework
requires 'strictures~2';                    # Enables strict and warnings with specific settings
requires 'namespace::clean';                # Removes declared and imported symbols from your compiled package
requires 'Mojo::UserAgent';                 # HTTP(S) and WebSocket connections
requires 'Mojo::UserAgent::Role::Queued';   # Connection limiting for UserAgent
requires 'Mojo::IOLoop';                    # Event loop required so the program does not exit and can wait for asynchronous operations
requires 'Mojo::JSON';                      # Translate between JSON and Perl hash for talking to Discord
requires 'Mojo::Util';                      # 
requires 'Mojo::Log';                       # Enables us to log information to disk instead of to screen
requires 'JSON::MaybeXS';                   # Provides proper escaping of Unicode characters so discord will encode them correctly
requires 'Compress::Zlib';                  # Handles incoming compressed Zlib blobs
requires 'Encode::Guess';                   # Used to determine if we are dealing with a compressed stream or not
requires 'Data::Dumper';                    # Debugging for complex objects
requires 'IO::Socket::SSL';                 # Used to fetch the WebSocket URL to connect to
requires 'Role::EventEmitter';              # Replaces callbacks, allows client apps to subscribe to events they want to handle
requires 'Time::Duration';                  # Allows us to calculate duration between two times, eg uptime
requires 'URI::Escape';                     # Make any text URL safe


# Unit Tests
requires 'Mojo::Base';
requires 'Test::More';
requires 'Mojolicious::Lite';
