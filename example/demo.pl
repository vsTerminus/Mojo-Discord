#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Chat::Bot;

my $bot = Chat::Bot->new(
    token       => 'TA5MTg0.CtXwmw.omfoNppF',   # You will need a valid Discord Bot token here.
    logdir      => '/path/to/logs/chatbot',     # This must be a directory you have permission to write to.
);

# This should be the last line of your file, because nothing below it will execute.
$bot->start();

