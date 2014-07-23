#!perl -T

use strict;
use Test::More tests => 3;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

my $pixel = $fb->pixel({'x'=>100,'y'=>200});
ok($pixel->{'red'} == 0 && $pixel->{'green'} == 0 && $pixel->{'blue'} ==0,'Starting color of pixel is black');

$fb->plot({'x'=>100,'y'=>200,'pixel_size'=>1});
$pixel = $fb->pixel({'x'=>100,'y'=>200});
ok($pixel->{'red'} == 255 && $pixel->{'green'} == 255 && $pixel->{'blue'} == 255,'Pixel color is now white');
