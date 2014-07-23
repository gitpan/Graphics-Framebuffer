#!perl -T

use strict;
use Test::More tests => 3;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

my $oldscreen = $fb->{'SCREEN'};
$fb->box({'x'=>10,'y'=>10,'xx'=>600,'yy'=>300,'filled'=>0});
ok($oldscreen ne $fb->{'SCREEN'},'Box frame was drawn');
$oldscreen = $fb->{'SCREEN'};
$fb->box({'x'=>20,'y'=>20,'xx'=>600,'yy'=>320,'filled'=>1});
ok($oldscreen ne $fb->{'SCREEN'},'Filled box was drawn');
