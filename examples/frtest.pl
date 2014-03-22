#!/usr/bin/perl

# This tests the various methods of the Graphics::Framebuffer module
# and shows the only way threads will work with it.

use strict;
use Switch;

use threads;
use Graphics::Framebuffer;

my @framebuffer;
my $Threads = 4;
foreach my $thr (1..$Threads) {
    push(@framebuffer,Graphics::Framebuffer->new());
}
my $screen_width = $framebuffer[0]->{'XRES'};
my $screen_height = $framebuffer[0]->{'YRES'};

$framebuffer[0]->cls();
my $cls = int(rand($screen_width));
foreach my $page (1..$Threads) {
    threads->create(
        sub {
            my $Page = shift;
            while(1) {
                attract($Page);
            }
        },
        $page - 1
    );
}
while(1) {
    threads->yield();
}


##############################################################################
##                             ATTRACT MODE                                 ##
##############################################################################
# Remeniscent of the "Atract Mode" of the old Atari 8 bit computers, this    #
# mode merely puts random patterns on the screen.                            #
##############################################################################

sub attract {
    my $Page = shift;
    my $red = int(rand(256));
    my $grn = int(rand(256));
    my $blu = int(rand(256));
    my $x   = int(rand($screen_width));
    my $y   = int(rand($screen_height));
    my $w   = int(rand($screen_width/4));
    my $h   = int(rand($screen_height/4));
    my $rx  = int(rand($screen_width/4));
    my $ry  = int(rand($screen_height/4));
    my $sd  = int(rand(360));
    my $ed  = int(rand(360));
    my $gr  = (rand(6)/10) + .5;
    my $mode = int(rand(5));
    my $type = int(rand(7));
    my $size = int(rand(3));
    $framebuffer[$Page]->cls() if ($x >= ($cls - 4) && $x <= ($cls + 4));

    $framebuffer[$Page]->set_color({'red' => $red,'green' => $grn,'blue' => $blu});
    $framebuffer[$Page]->draw_mode($mode);
    $framebuffer[$Page]->clip_rset({'x' => 0,'y' => 0,'width' => $screen_width-1,'height' => $screen_height-1});
    switch ($type) {
        case 0 {
            $framebuffer[$Page]->plot({'x' => $x,'y' => $y,'pixel_size' => 1});
        }
        case 1 {
            $framebuffer[$Page]->plot({'x' => $x,'y' => $y,'pixel_size' => $size});
            $framebuffer[$Page]->drawto({'x' => $w,'y' => $h,'pixel_size' => $size});
        }
        case 2 {
            $framebuffer[$Page]->circle({'x' => $x,'y' => $y,'radius' => $rx,'filled' => int(rand(2)),'pixel_size' => $size});
        }
        case 3 {
            $framebuffer[$Page]->ellipse({'x' => $x,'y' => $y,'xradius' => $rx,'yradius' => $ry,'filled' => int(rand(2)),'factor' => 1,'pixel_size' => $size});
        }
        case 4 {
            $framebuffer[$Page]->rbox({'x' => $x,'y' => $y,'width' => $w,'height' => $h,'filled' => (int(rand(2))),'pixel_size' => $size});
        }
        case 5 {
            $framebuffer[$Page]->draw_arc({'x' => $x,'y' => $y,'radius' => $ry,'start_degrees' => $sd,'end_degrees' => $ed,'granularity' => $gr,'mode' => (int(rand(3))),'pixel_size' => $size});
        }
        case 6 {
            my @poly;
            foreach my $count (0..int(rand(10))) {
                push(@poly,int(rand($screen_width)));
                push(@poly,int(rand($screen_height)));
            }
            $framebuffer[$Page]->polygon({'pixel_size' => $size,'coordinates' => \@poly});
        }
        else { # This can be a large memory hog.  Disabled for the moment.
            $framebuffer[$Page]->clip_set({'x' => $x-50,'y' => $y-50,'xx' => $x+50,'yy' => $y+50});
            fill({'x' => $x,'y' => $y});
        }
    }
    $framebuffer[$Page]->clip_reset();
    return($Page);
}

__END__

__C__

