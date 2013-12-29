package Graphics::Framebuffer;

use strict;
no strict 'vars';
use 5.014;
use Switch; # Yes, a touch of new Perl.
use Math::Trig qw(:pi);

##########################################################
##       PURE PERL 16/32 bit GRAPHICS ROUTINES          ##
##########################################################
#            Copyright 2004 Richard Kelsch               #
#                All Rights Reserved                     #
##########################################################

# Currently, I cannot multithread these objects, as it breaks the memory mapping
# of the framebuffer and $SCREEN variable, due to how Perl copies all variables.
# Using Threads::shared doesn't work either.  I have some ideas to implement
# threading to speed things up a bit.  Nevertheless, these routines are pretty
# fast considering they are all interpreted and not compiled, and single-threaded.

# I cannot guarantee this will work on your video card, but I have successfully
# tested it on NVidia GeForce, AMD Radeon, Matrox,  and VirtualBox displays.
# However, you MUST remember, your video driver MUST be framebuffer based.  The
# proprietary Nvidia and AMD drivers will NOT work with this module.  You must use
# the open source video drivers, such as Nouveau, to be able to use this library.
# Also, it is not going to work from within X, so don't even try it.  This is a
# console only graphics library.

# I highly suggest you use 32 bit mode and avoid 16 bit, as it has been a long time
# since I tested it on a 16 bit graphics mode.

use Sys::Mmap;      # Absolutely necessary to map the screen to a string.
use Imager;         # This is used for TrueType font printing.
# use Imager::Fill; # Not used yet, but coming soon.
# use Data::Dumper::Simple; # I use this for debugging.

BEGIN {
    require Exporter;
    # set the version for version checking
    our $VERSION   = 4.02;
    # Inherit from Exporter to export functions and variables
    our @ISA       = qw(Exporter);
    # Functions and variables which are exported by default
    our @EXPORT    = qw();
    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw();
}

DESTROY {
    my $self = shift;
    $self->screen_close();
}

sub new {
    my $class = shift;
    my @dummy; # Just a temporary generic array for excess data returned from get_info
    my $self  = {
	'SCREEN'      => '',
        # Set up the user defined graphics primitives and attributes default values
        'I_COLOR'     => undef,
        'X'           => 0,
        'Y'           => 0,
        'X_CLIP'      => 0,
        'Y_CLIP'      => 0,
        'YY_CLIP'     => undef,
        'XX_CLIP'     => undef,
        'COLOR'       => undef,
        'DRAW_MODE'   => 0,
        'B_COLOR'     => undef,
        'NORMAL_MODE' => 0,
        'XOR_MODE'    => 1,
        'OR_MODE'     => 2,
        'AND_MODE'    => 3,
        'MASK_MODE'   => 4,
        'CLIPPED'     => 0,

        # Set up the Framebuffer driver "constants" defaults
        'FBIOGET_VSCREENINFO'      => 0x4600,
        'FBIOGET_FSCREENINFO'      => 0x4602,
        'FBINFO_HWACCEL_COPYAREA'  => 0x0100, # I have never been able to get these
        'FBINFO_HWACCEL_FILLRECT'  => 0x0200, # three HWACCEL ioctls to work
        'FBINFO_HWACCEL_IMAGEBLIT' => 0x0400, #
        'FBioget_vscreeninfo'      => 'I24',
        'FBioget_fscreeninfo'      => 'A16LI4S3ILI2S',
        'FBinfo_hwaccel_copyarea'  => 'I6',
        'FBinfo_hwaccel_fillrect'  => 'I6',
        'FBinfo_hwaccel_imageblit' => 'I6C1I2'
    };
    open($self->{'FB'},'+</dev/fb0') || return(undef);
    binmode($self->{'FB'});

    (
        $self->{'xres'},
        $self->{'yres'},
        $self->{'xres_virtual'},
        $self->{'yres_virtual'},
        $self->{'xoffset'},
        $self->{'yoffset'},
        $self->{'bits_per_pixel'},
        $self->{'grayscale'},
        $self->{'bitfields'},
        $self->{'nonstd'},
        $self->{'activate'},
        $self->{'height'},
        $self->{'width'},
        $self->{'accel_flags'},
        $self->{'pixclock'},
        $self->{'left_margin'},
        $self->{'right_margin'},
        $self->{'upper_margin'},
        $self->{'lower_margin'},
        $self->{'hsync_len'},
        $self->{'vsync_len'},
        $self->{'sync'},
        $self->{'vmode'},
        @dummy
    ) = get_info($self->{'FBIOGET_VSCREENINFO'},$self->{'FBioget_vscreeninfo'},$self->{'FB'});

    (
        $self->{'id'},
        $self->{'smem_start'},
        $self->{'smem_len'},
        $self->{'type'},
        $self->{'type_aux'},
        $self->{'visual'},
        $self->{'xpanstep'},
        $self->{'ypanstep'},
        $self->{'ywrapstep'},
        $self->{'line_length'},
        $self->{'mmio_start'},
        $self->{'mmio_len'},
        $self->{'accel'},
        @dummy
    ) = get_info($self->{'FBIOGET_FSCREENINFO'},$self->{'FBioget_fscreeninfo'},$self->{'FB'});
    $self->{'VXRES'}          = $self->{'xres_virtual'};
    $self->{'VYRES'}          = $self->{'yres_virtual'};
    $self->{'XRES'}           = $self->{'xres'};
    $self->{'YRES'}           = $self->{'yres'};
    $self->{'XOFFSET'}        = $self->{'xoffset'} || 0;
    $self->{'YOFFSET'}        = $self->{'yoffset'} || 0;
    $self->{'BITS'}           = $self->{'bits_per_pixel'};
    $self->{'BYTES'}          = $self->{'BITS'} / 8;
    $self->{'PIXELS'}         = (($self->{'XOFFSET'} + $self->{'VXRES'}) * ($self->{'YOFFSET'} + $self->{'VYRES'}));
    $self->{'SIZE'}           = $self->{'PIXELS'} * $self->{'BYTES'};
    $self->{'smem_len'}       = $self->{'BYTES'} * ($self->{'VXRES'} * $self->{'VYRES'}) if (! defined($self->{'smem_len'}) || $self->{'smem_len'} <= 0);
    $self->{'BYTES_PER_LINE'} = int($self->{'smem_len'} / $self->{'VYRES'});

    bless ($self,$class);

    attribute_reset($self);
    # Now that everything is set up, let's map the framebuffer to SCREEN
    mmap($self->{'SCREEN'},$self->{'smem_len'},PROT_READ|PROT_WRITE,MAP_SHARED,$self->{'FB'});

    return $self;
}
sub screen_close {
    ##########################################################
    ##                     SCREEN CLOSE                      #
    ##########################################################
    # Unmaps SCREEN and closes the framebuffer               #
    ##########################################################
    my $self = shift;
    munmap($self->{'SCREEN'}) if (defined($self->{'SCREEN'}));
    close($self->{'FB'}) if (defined($self->{'FB'}));
    delete($self->{'SCREEN'});
    delete($self->{'FB'});
}
sub screen_dimensions {
    ##########################################################
    ##                   SCREEN DIMENSIONS                  ##
    ##########################################################
    # Returns the size of the framebuffer in X,Y pixel       #
    # values.                                                #
    ##########################################################
    my $self = shift;
    return($self->{'xres'},$self->{'yres'});
}
sub draw_mode {
    ##########################################################
    ##                      DRAW MODE                       ##
    ##########################################################
    # Sets or returns the drawing mode.                      #
    ##########################################################
    my $self = shift;
    if (@_) {
        $self->{'DRAW_MODE'} = int(shift);
    } else {
        return($self->{'DRAW_MODE'});
    }
}
sub clear_screen {
    ##########################################################
    ##                     CLEAR SCREEN                     ##
    ##########################################################
    # Fills the entire screen with the background color fast #
    ##########################################################
    my $self = shift;
    $self->blit_write({'x' => 0,'y' => 0,'width' => $self->{'XRES'},'height' => $self->{'YRES'},'image' => chr(0) x $self->{'SIZE'}},0);
}
sub cls {
    my $self = shift;
    $self->clear_screen();
}
sub attribute_reset {
    ##########################################################
    ##                    ATTRIBUTE RESET                   ##
    ##########################################################
    # Resets the plot point at 0,0.  Resets clipping the     #
    # current screen size.  Resets the global color to white #
    # Resets drawing mode to normal.                         #
    ##########################################################
    my $self = shift;

    $self->{'X'} = 0;
    $self->{'Y'} = 0;
    $self->set_color({'red' => 255,'green' => 255,'blue' => 255});
    $self->{'DRAW_MODE'} = $self->{'NORMAL_MODE'};
    $self->set_b_color({'red' => 0,'green' => 0,'blue' => 0});
    $self->clip_reset;
}
sub plot {
    ##########################################################
    ##                         PLOT                         ##
    ##########################################################
    # Set a single pixel in the globally set color at        #
    # position x,y with the given pixel size (or default).   #
    # Clipping applies.                                      #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x    = int($params->{'x'}); # Ignore decimals
    my $y    = int($params->{'y'});
    my $size = int($params->{'pixel_size'} || 1);
    my ($c,$index);

    if ($size > 1) {
        $self->circle({'x' => $x,'y' => $y,'radius' => ($size/2),'filled' => 1,'pixel_size' => 1});
    } else {
        # Only plot if the pixel is within the clipping region
        if (
            ($x <= $self->{'XX_CLIP'}) &&
            ($y <= $self->{'YY_CLIP'}) &&
            ($x >= $self->{'X_CLIP'}) &&
            ($y >= $self->{'Y_CLIP'})
        ) {
            $index = ($self->{'BYTES_PER_LINE'} * ($y + $self->{'YOFFSET'})) + ($x * $self->{'BYTES'});
            if ($self->{'DRAW_MODE'} == $self->{'NORMAL_MODE'}) {
                substr($self->{'SCREEN'},$index,$self->{'BYTES'}) = $self->{'COLOR'};
            } else {
                $c = substr($self->{'SCREEN'},$index,$self->{'BYTES'});
                switch($self->{'DRAW_MODE'}) {
                    case ($self->{'XOR_MODE'}) {
#                        $c = $c ^ $self->{'COLOR'};
                        $c ^= $self->{'COLOR'};
                    }
                    case ($self->{'OR_MODE'}) {
#                        $c = $c | $self->{'COLOR'};
                        $c |= $self->{'COLOR'};
                    }
                    case ($self->{'AND_MODE'}) {
#                        $c = $c & $self->{'COLOR'};
                        $c &= $self->{'COLOR'};
                    }
                    case ($self->{'MASK_MODE'}) {
                        $c = $self->{'COLOR'} if ($self->{'COLOR'} ne $self->{'B_COLOR'});
                    }
                    case ($self->{'UNMASK_MODE'}) {
                        $c = $self->{'COLOR'} if ($self->pixel($x,$y) eq $self->{'B_COLOR'});
                    }
                }
                substr($self->{'SCREEN'},$index,$self->{'BYTES'}) = $c;
            }
        }
        $self->{'X'} = $x;
        $self->{'Y'} = $y;
    }
}
sub drawto {
    ##########################################################
    ##                        DRAWTO                        ##
    ##########################################################
    # Draws a line in the global color from the last plotted #
    # position to the position x,y.  Clipping applies        #
    #                                                        #
    # Perfectly horizontal line drawing is optimized by      #
    # using the BLIT functions.  This assists greatly with   #
    # drawing filled objects.  In fact, it's hundreds of     #
    # times faster!                                          #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x_end = int($params->{'x'}); # Ignore decimals
    my $y_end = int($params->{'y'});
    my $size  = int($params->{'pixel_size'} || 1);

    my ($width,$height);
    my $start_x = $self->{'X'};
    my $start_y = $self->{'Y'};
    if ($start_x > $x_end) {
        $width = $start_x - $x_end;
    } else {
        $width = $x_end - $start_x;
    }
    if ($start_y > $y_end) {
        $height = $start_y - $y_end;
    } else {
        $height = $y_end - $start_y;
    }
    if (($x_end == $start_x) && ($y_end == $start_y)) {
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    } elsif ($x_end == $start_x) {
        if ($start_y > $y_end) {
            while($start_y >= $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y--;
            }
        } else {
            while($start_y <= $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y++;
            }
        }
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    } elsif ($y_end == $start_y) {
        if ($size == 1) {
            if ($start_x > $x_end) {
                $self->blit_write({'x' => $x_end,'y' => $y_end,'width' => $width,'height' => 1,'image' => $self->{'COLOR'} x $width}); # Blitting a horizontal line is much faster!
            } else {
                $self->blit_write({'x' => $start_x,'y' => $start_y,'width' => $width,'height' => 1,'image' => $self->{'COLOR'} x $width}); # Blitting a horizontal line is much faster!
            }
        } else {
            for(my $ty=($y_end - ($size / 2));$ty<=($y_end + ($size / 2));$ty++) {
                if ($start_x > $x_end) {
                    $self->blit_write({'x' => $x_end,'y' => $ty,'width' => $width,'height' => 1,'image' => $self->{'COLOR'} x $width}); # Blitting a horizontal line is much faster!
                } else {
                    $self->blit_write({'x' => $start_x,'y' => $ty,'width' => $width,'height' => 1,'image' => $self->{'COLOR'} x $width}); # Blitting a horizontal line is much faster!
                }
            }
        }
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    } elsif ($width > $height) {
        my $factor = $height / $width;
        if (($start_x < $x_end) && ($start_y < $y_end)) {
            while($start_x < $x_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y += $factor;
                $start_x++;
            }
        } elsif(($start_x > $x_end) && ($start_y < $y_end)) {
            while($start_x > $x_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y += $factor;
                $start_x--;
            }
        } elsif(($start_x < $x_end) && ($start_y > $y_end)) {
            while($start_x < $x_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y -= $factor;
                $start_x++;
            }
        } elsif(($start_x > $x_end) && ($start_y > $y_end)) {
            while($start_x>$x_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_y -= $factor;
                $start_x--;
            }
        }
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    } elsif ($width < $height) {
        my $factor = $width / $height;
        if (($start_x < $x_end) && ($start_y < $y_end)) {
            while($start_y < $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x += $factor;
                $start_y++;
            }
        } elsif(($start_x > $x_end) && ($start_y < $y_end)) {
            while($start_y < $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x -= $factor;
                $start_y++;
            }
        } elsif(($start_x < $x_end) && ($start_y > $y_end)) {
            while($start_y > $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x += $factor;
                $start_y--;
            }
        } elsif(($start_x > $x_end) && ($start_y > $y_end)) {
            while($start_y > $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x -= $factor;
                $start_y--;
            }
        }
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    } else {  # $width == $height
        if (($start_x < $x_end) && ($start_y < $y_end)) {
            while($start_y<$y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x++;
                $start_y++;
            }
        } elsif(($start_x > $x_end) && ($start_y < $y_end)) {
            while($start_y < $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x--;
                $start_y++;
            }
        } elsif(($start_x < $x_end) && ($start_y > $y_end)) {
            while($start_y > $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x++;
                $start_y--;
            }
        } elsif(($start_x > $x_end) && ($start_y > $y_end)) {
            while($start_y > $y_end) {
                $self->plot({'x' => $start_x,'y' => $start_y,'pixel_size' => $size});
                $start_x--;
                $start_y--;
            }
        }
        $self->plot({'x' => $x_end,'y' => $y_end,'pixel_size' => $size});
    }
}
sub draw_arc {
    ##########################################################
    ##                       DRAW ARC                       ##
    ##########################################################
    # Draws an arc of a circle at point x,y.                 #
    #  $x = x of center of circle                            #
    #  $y = y of center of circle                            #
    #  $radius = radius of circle                            #
    #  $start_degrees = starting point, in degrees, of arc   #
    #  $end_degrees = ending point, in degrees, of arc       #
    #  $granularity = This is used for accuracy in drawing   #
    #                 the arc.  The smaller the number, the  #
    #                 more accurate the arc is drawn, but it #
    #                 is also slower.  Values between 0.1    #
    #                 and 0.01 are usually good.             #
    #  $mode = Specifies the drawing mode.                   #
    #           0 > arc only                                 #
    #           1 > Filled pie section                       #
    #           2 > Poly arc.  Draws a line from x,y to the  #
    #               beginning and ending arc position.       #
    ##########################################################
    # This isn't exactly the fastest routine out there,      #
    # hence the "granularity" parameter, but it is pretty    #
    # neat.                                                  #
    ##########################################################
    my $self          = shift;
    my $params        = shift;

    my $x             = int($params->{'x'});
    my $y             = int($params->{'y'});
    my $radius        = int($params->{'radius'});
    my $start_degrees = 0 + sprintf('%.03f',$params->{'start_degrees'});
    my $end_degrees   = 0 + sprintf('%.03f',$params->{'end_degrees'});
    my $granularity   = 0 + sprintf('%.03f',$params->{'granularity'});
    my $mode          = int($params->{'mode'});
    my $size          = int($params->{'pixel_size'} || 1);
    $size = 1 if ($mode == 1);
    my ($sx,$sy,$degrees,$ox,$oy);

    $degrees = $start_degrees;
    if ($start_degrees > $end_degrees) {
        do {
            $sx = $x - ($radius * sin(($degrees * pi) / 180));
            $sy = $y - ($radius * cos(($degrees * pi) / 180));
            if (($sx <=> $ox) || ($sy <=> $oy)) {
                switch($mode) {
                    case(0) { # Ordinary arc
                        $self->plot({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                    }
                    case(1) { # Filled arc
                        $self->plot({'x' => $x,'y' => $y,'pixel_size' => $size});
                        $self->drawto({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                    }
                    case(2) { # Poly arc
                        if ($degrees == $start_degrees) {
                            $self->plot({'x' => $x,'y' => $y,'pixel_size' => $size});
                            $self->drawto({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                        } else {
                            $self->plot({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                        }
                    }
                }
                $ox = $sx;
                $oy = $sy;
            }
            $degrees += $granularity;
        } until ($degrees >= 360);
        $degrees = 0;
    }
    do {
        $sx = $x - ($radius * sin(($degrees * pi) / 180));
        $sy = $y - ($radius * cos(($degrees * pi) / 180));
        if (($sx <=> $ox) || ($sy <=> $oy)) {
            switch($mode) {
                case(0) { # Ordinary arc
                    $self->plot({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                }
                case(1) { # Filled arc
                    $self->plot({'x' => $x,'y' => $y,'pixel_size' => $size});
                    $self->drawto({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                }
                case(2) { # Poly arc
                    if ($degrees == $start_degrees) {
                        $self->plot({'x' => $x,'y' => $y,'piel_size' => $size});
                        $self->drawto({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                    } else {
                        $self->plot({'x' => $sx,'y' => $sy,'pixel_size' => $size});
                    }
                }
            }
            $ox = $sx;
            $oy = $sy;
        }
        $degrees += $granularity;
    } until ($degrees >= $end_degrees);
    if ($mode == 2) {
        $self->plot({'x' => $x,'y' => $y,'pixel_size' => $size});
        $self->drawto({'x' => $sx,'y' => $sy,'pixel_size' => $size});
    }
}
sub ellipse {
    ##########################################################
    ##                        ELLIPSE                       ##
    ##########################################################
    # Draw an ellipse at center position x,y with XRadius,   #
    # YRadius.  Either a filled out outline is drawn based   #
    # on the value of $filled.  The optional factor value    #
    # varies from the default 1 to change the look and       #
    # nature of the output.  Clipping Applies                #
    #                                                        #
    # The routine even works properly for XOR mode when      #
    # filled ellipses are drawn as well.  This was solved by #
    # drawing only if the X or Y position changed.           #
    ##########################################################
    my $self    = shift;
    my $params  = shift;

    my $cx      = int($params->{'x'});
    my $cy      = int($params->{'y'});
    my $XRadius = int($params->{'xradius'});
    my $YRadius = int($params->{'yradius'});

    $XRadius    = 1 if ($XRadius < 1);
    $YRadius    = 1 if ($YRadius < 1);
    my $filled  = int($params->{'filled'});
    my $fact    = $params->{'factor'} || 0;
    my $size    = $params->{'pixel_size'} || 1;
    $size = 1 if ($filled);

    my ($old_cyy,$old_cy_y);
    if ($fact == 0) {
        $fact = 1;
    }
    my $TwoASquare   = (2 * ($XRadius * $XRadius)) * $fact;
    my $TwoBSquare   = (2 * ($YRadius * $YRadius)) * $fact;
    my $x            = $XRadius;
    my $y            = 0;
    my $XChange      = ($YRadius * $YRadius) * (1 - (2 * $XRadius));
    my $YChange      = ($XRadius * $XRadius);
    my $EllipseError = 0;
    my $StoppingX    = $TwoBSquare * $XRadius;
    my $StoppingY    = 0;
    while ($StoppingX >= $StoppingY) {
        my $cxx  = $cx + $x;
        my $cx_x = $cx - $x;
        my $cyy  = $cy + $y;
        my $cy_y = $cy - $y;
        if ($filled) {
            if ($cyy <=> $old_cyy) {
                $self->plot({'x' => $cxx,'y' => $cyy,'pixel_size' => $size});
                $self->drawto({'x' => $cx_x,'y' => $cyy,'pixel_size' => $size});
                $old_cyy = int($cyy);
            }
            if (($cy_y <=> $old_cy_y) && ($cyy <=> $cy_y)) {
                $self->plot({'x' => $cx_x,'y' => $cy_y,'pixel_size' => $size});
                $self->drawto({'x' => $cxx,'y' => $cy_y,'pixel_size' => $size});
                $old_cy_y = int($cy_y);
            }
        } else {
            $self->plot({'x' => $cxx,'y' => $cyy,'pixel_size' => $size});
            $self->plot({'x' => $cx_x,'y' => $cyy,'pixel_size' => $size});
            $self->plot({'x' => $cx_x,'y' => $cy_y,'pixel_size' => $size}) if ($cyy <=> $cy_y);
            $self->plot({'x' => $cxx,'y' => $cy_y,'pixel_size' => $size}) if ($cyy <=> $cy_y);
        }
        $y++;
        $StoppingY    += $TwoASquare;
        $EllipseError += $YChange;
        $YChange      += $TwoASquare;
        if ((($EllipseError * 2) + $XChange) > 0) {
            $x--;
            $StoppingX    -= $TwoBSquare;
            $EllipseError += $XChange;
            $XChange      += $TwoBSquare;
        }
    }
    $old_cyy      = 0;
    $old_cy_y     = 0;
    $x            = 0;
    $y            = $YRadius;
    $XChange      = ($YRadius * $YRadius);
    $YChange      = ($XRadius * $XRadius) * (1 - 2 * $YRadius);
    $EllipseError = 0;
    $StoppingX    = 0;
    $StoppingY    = $TwoASquare * $YRadius;
    while ($StoppingX <= $StoppingY) {
        my $cxx  = $cx + $x;
        my $cx_x = $cx - $x;
        my $cyy  = $cy + $y;
        my $cy_y = $cy - $y;
        if ($filled) {
            if ($cyy <=> $old_cyy) {
                $self->plot({'x' => $cxx,'y' => $cyy,'pixel_size' => $size});
                $self->drawto({'x' => $cx_x,'y' => $cyy,'pixel_size' => $size});
                $old_cyy = int($cyy);
            }
            if (($cy_y <=> $old_cy_y) && ($cyy <=> $cy_y)) {
                $self->plot({'x' => $cx_x,'y' => $cy_y,'pixel_size' => $size});
                $self->drawto({'x' => $cxx,'y' => $cy_y,'pixel_size' => $size});
                $old_cy_y = int($cy_y);
            }
        } else {
            $self->plot({'x' => $cxx,'y' => $cyy,'pixel_size' => $size});
            $self->plot({'x' => $cx_x,'y' => $cyy,'pixel_size' => $size}) if ($cxx <=> $cx_x);
            $self->plot({'x' => $cx_x,'y' => $cy_y,'pixel_size' => $size}) if ($cxx <=> $cx_x);
            $self->plot({'x' => $cxx,'y' => $cy_y,'pixel_size' => $size});
        }
        $x++;
        $StoppingX    += $TwoBSquare;
        $EllipseError += $XChange;
        $XChange      += $TwoBSquare;
        if ((($EllipseError * 2) + $YChange) > 0) {
            $y--;
            $StoppingY    -= $TwoASquare;
            $EllipseError += $YChange;
            $YChange      += $TwoASquare;
        }
    }
}
sub circle {
    ##########################################################
    ##                        CIRCLE                        ##
    ##########################################################
    # A wrapper to ELLIPSE it only needs X, Y, and Radius    #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x      = int($params->{'x'});
    my $y      = int($params->{'y'});
    my $r      = int($params->{'radius'});
    my $filled = int($params->{'filled'} || 0);
    my $size   = int($params->{'pixel_size'} || 1);
    $self->ellipse({'x' => $x,'y' => $y,'xradius' => $r,'yradius' => $r,'filled' => $filled,'factor' => 1,'pixel_size' => $size});
}
sub polygon {
    ##########################################################
    ##                        POLYGON                       ##
    ##########################################################
    # Creates an empty polygon drawn in the global color     #
    # value.  An array of x,y values is passed to it.  The   #
    # last x,y combination is connected automatically with   #
    # the first to close the polygon.  All x,y values are    #
    # absolute, not relative.  Clipping applies.             #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $size     = int($params->{'pixel_size'} || 1);
    my @coords   = @{$params->{'coordinates'}};
    my ($xx,$yy) = (int(shift(@coords)),int(shift(@coords)));
    my ($x,$y);
    $self->plot({'x' => $xx,'y' => $yy,'pixel_size' => $size});
    while(scalar(@coords)) {
        $x = int(shift(@coords));
        $y = int(shift(@coords));
        $self->drawto({'x' => $x,'y' => $y,'pixel_size' => $size});
    }
    $self->drawto({'x' => $xx,'y' => $yy,'pixel_size' => $size});
    $self->plot({'x' => $xx,'y' => $yy,'pixel_size' => $size}) if ($self->{'DRAW_MODE'} == 1);
}
sub rbox {
    ##########################################################
    ##                         RBOX                         ##
    ##########################################################
    # And alternate method to call BOX.  It uses width and   #
    # height values instead of absolute coordinates for the  #
    # bottom right corner.                                   #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x      = int($params->{'x'});
    my $y      = int($params->{'y'});
    my $w      = int($params->{'width'});
    my $h      = int($params->{'height'});
    my $filled = int($params->{'filled'} || 0);
    my $size   = int($params->{'pixel_size'} || 1);
    $size = 1 if ($filled);
    my $xx = $x + $w;
    my $yy = $y + $h;
    $self->box({'x' => $x,'y' => $y,'xx' => $xx,'yy' => $yy,'filled' => $filled,'pixel_size' => $size});
}
sub box {
    ##########################################################
    ##                          BOX                         ##
    ##########################################################
    # Draws a box from point x,y to point xx,yy, either as   #
    # an outline if "filled" is 0 or as a filled block if    #
    # "filled" is 1.                                         #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x      = int($params->{'x'});
    my $y      = int($params->{'y'});
    my $xx     = int($params->{'xx'});
    my $yy     = int($params->{'yy'});
    my $filled = int($params->{'filled'} || 0);
    my $size   = int($params->{'pixel_size'} || 1);
    $size = 1 if ($filled);
    my ($count,$data,$w,$h);
    # This puts $x,$y,$xx,$yy in their correct order if backwards.
    # $x must always be less than $xx
    # $y must always be less than $yy
    if ($x > $xx) {
        ($x,$xx) = ($xx,$x);
    }
    if ($y > $yy) {
        ($y,$yy) = ($yy,$y);
    }
    if ($filled == 1) {
        $w = abs($xx - $x);
        $h = abs($yy - $y);
        $self->blit_write({'x' => $x,'y' => $y,'width' => $w,'height' => $h,'image' => $self->{'COLOR'} x ($w * $h)});
    } else {
        $self->polygon({'pixel_size' => $size,'coordinates' => [$x,$y,$xx,$y,$xx,$yy,$x,$yy]});
    }
}
sub set_color {
    ##########################################################
    ##                        COLOR                         ##
    ##########################################################
    # Returns a compacted string with the 32 bit encoded RGB #
    # color value passed to it as separate RGB values.       #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $R = int($params->{'red'}) & 255;
    my $G = int($params->{'green'}) & 255;
    my $B = int($params->{'blue'}) & 255;
    if ($self->{'BITS'} == 32) {
        $self->{'COLOR'} = chr($B).chr($G).chr($R).chr(255);
    } else {
        $R = int($R / 8);
        $G = int($G / 8);
        $B = int($B / 8);
        $self->{'COLOR'} = ($R << 11) + ($G << 6) + $B;
        $self->{'COLOR'} = pack('S',$self->{'COLOR'});
    }
    $self->{'I_COLOR'} = Imager::Color->new($R,$G,$B);
}
sub set_b_color {
    ##########################################################
    ##                  SET BACKGROUND COLOR                ##
    ##########################################################
    # Sets the background color to be the Red, Green, and    #
    # Blue values passed in.                                 #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $R = int($params->{'red'}) & 255;
    my $G = int($params->{'green'}) & 255;
    my $B = int($params->{'blue'}) & 255;
    if ($self->{'BITS'} == 32) {
        $self->{'B_COLOR'} = chr($B).chr($G).chr($R).chr(255);
    } else {
        $R = int($R / 8);
        $G = int($G / 8);
        $B = int($B / 8);
        $self->{'B_COLOR'} = ($R << 11) + ($G << 6) + $B;
        $self->{'B_COLOR'} = pack('S',$self->{'COLOR'});
    }
}
sub pixel {
    ##########################################################
    ##                         PIXEL                        ##
    ##########################################################
    # Return the Red, Green, and Blue color values of a      #
    # particular pixel.                                      #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x = int($params->{'x'});
    my $y = int($params->{'y'});
    if (($x > $self->{'XX_CLIP'}) || ($y > $self->{'YY_CLIP'}) || ($x < $self->{'X_CLIP'}) || ($y < $self->{'Y_CLIP'})) {
        return(undef);
    } else {
        my ($color,$R,$G,$B,$A);
        my $index = ($self->{'BYTES_PER_LINE'} * ($y + $self->{'YOFFSET'})) + ($x * $self->{'BYTES'});
        $color = substr($self->{'SCREEN'},$index,$self->{'BYTES'});
        if ($self->{'BITS'} == 32) {
            ($B,$G,$R,$A) = unpack('C4',$color);
        } else {
            $A = unpack('S',$color);
            $color = pack('S',$A);
            $B = $A & 31;
            $G = ($A >> 6) & 31;
            $R = ($A >> 11) & 31;
            $R = int($R * 8);
            $G = int($G * 8);
            $B = int($B * 8);
        }
        return({'red' => $R,'green' => $G,'blue' => $B,'raw' => $color});
    }
}
sub fill {
    ##########################################################
    ##                      FLOOD FILL                      ##
    ##########################################################
    # Starts at x,y and first samples the color currently    #
    # active at the point and determines that color to be    #
    # the background color, and proceeds to fill in with the #
    # current global color until the background is replaced  #
    # with the new color or a different color is found.      #
    # Clipping applies.  THIS CAN CHOW DOWN ON MEMORY UNTIL  #
    # IT FINISHES, DUE TO ITS RECURSIVE NATURE!!             #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x = int($params->{'x'});
    my $y = int($params->{'y'});
    my ($BR,$BG,$BB,$back) = $self->pixel({'x' => $x,'y' => $y});
    $self->flood({'x' => $x,'y' => $y,'background' => $back}) if ($back ne $self->{'COLOR'});
}
sub flood {
    ##########################################################
    ##                         FLOOD                        ##
    ##########################################################
    # Used by FLOOD FILL above to flood file an empty space  #
    # It starts at X,Y.  This can be a memory hog due to the #
    # recursive calls it makes.                              #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x    = int($params->{'x'});
    my $y    = int($params->{'y'});
    my $back = $params->{'background'};
    my ($r,$g,$b,$f_color) = $self->pixel({'x' => $x,'y' => $y});
    if (($x >= $self->{'X_CLIP'}) && ($x <= $self->{'XX_CLIP'}) && ($y >= $self->{'Y_CLIP'}) && ($y <= $self->{'YY_CLIP'}) && ($f_color eq $back)) {
        $self->plot({'x' => $x,'y' => $y,'pixel_size' => 1});
        $self->flood({'x' => $x,'y' => $y+1,'background' => $back});
        $self->flood({'x' => $x,'y' => $y-1,'background' => $back});
        $self->flood({'x' => $x+1,'y' => $y,'background' => $back});
        $self->flood({'x' => $x-1,'y' => $y,'background' => $back});
    }
}
sub replace_color {
    ##########################################################
    ##                    REPLACE COLOR                     ##
    ##########################################################
    # This handy routine replaces one color with another     #
    # within the entire screen region.  The old RGB values   #
    # are passed along with the new in that order.  Clipping #
    # is in the experimental stage right now                 #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $old_r = int($params->{'old_red'});
    my $old_g = int($params->{'old_green'});
    my $old_b = int($params->{'old_blue'});
    my $new_r = int($params->{'new_red'});
    my $new_g = int($params->{'new_green'});
    my $new_b = int($params->{'new_blue'});
    if ($self->{'BITS'} < 32) {
        $old_r = int($old_r / 8);
        $old_g = int($old_g / 8);
        $old_b = int($old_b / 8);
        $new_r = int($new_r / 8) * 8;
        $new_g = int($new_g / 8) * 8;
        $new_b = int($new_b / 8) * 8;
    }
    $self->set_color({'red' => $new_r,'green' => $new_g,'blue' => $new_b});
    my $old_mode = $self->{'DRAW_MODE'};
    $self->{'DRAW_MODE'} = $self->{'NORMAL_MODE'};

    for(my $y=$self->{'Y_CLIP'};$y<=$self->{'YY_CLIP'};$y++) {
        for(my $x=$self->{'X_CLIP'};$x<=$self->{'XX_CLIP'};$x++) {
            my $p = $self->pixel({'x' => $x,'y' => $y,'pixel_size' => 1});
            my ($r,$g,$b) = ($p->{'red'},$p->{'green'},$p->{'blue'});
            if (($r == $old_r) && ($g == $old_g) && ($b == $old_b)) {
                $self->plot({'x' => $x,'y' => $y,'pixel_size' => 1});
            }
        }
    }
    $self->{'DRAW_MODE'} = $old_mode;
}
sub blit_copy {
    ##########################################################
    ##                       BLIT COPY                      ##
    ##########################################################
    # COPIES A SQUARE OF GRAPHIC DATA FROM X,Y,W,H TO XX,YY  #
    # IT COPIES IN THE CURRENT DRAWING MODE                  #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x  = int($params->{'x'});
    my $y  = int($params->{'y'});
    my $w  = int($params->{'width'});
    my $h  = int($params->{'height'});
    my $xx = int($params->{'x_dest'});
    my $yy = int($params->{'y_dest'});

#    set_info($self->{'FBINFO_HWACCEL_COPYAREA'},$self->{'FBinfo_hwaccel_copyarea'},$self->{'FB'},$xx,$yy,$w,$h,$x,$y);
    $self->blit_write({'x' => $xx,'y' => $yy,%{$self->blit_read({'x' => $x,'y' => $y,'width' => $w,'height' => $h})}});
}
sub blit_read {
    ##########################################################
    ##                       BLIT READ                      ##
    ##########################################################
    # Reads in a block of screen data at x,y,w,h and returns #
    # the block of raw data.                                 #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x = int($params->{'x'});
    my $y = int($params->{'y'});
    my $w = int($params->{'width'});
    my $h = int($params->{'height'});

    $x = 0 if ($x < 0);
    $y = 0 if ($y < 0);
    $w = $self->{'XRES'} if ($w > $self->{'XRES'});
    $h = $self->{'YRES'} if ($h > $self->{'YRES'});

    my $yend = $y + $h;
    my $W    = $w * $self->{'BYTES'};
    my $XX   = $x * $self->{'BYTES'};
    my ($index,$scrn,$line);
    for ($line=$y;$line<$yend;$line++) {
        $index = ( $self->{'BYTES_PER_LINE'} * ( $line + $self->{'YOFFSET'} ) ) + $XX;
        $scrn .= substr($self->{'SCREEN'},$index,$W);
    }

    return({'width' => $w,'height' => $h,'image' => $scrn});
}
sub blit_write {
    ##########################################################
    ##                       BLIT WRITE                     ##
    ##########################################################
    # Writes a previously read block of screen data at xx,yy #
    # w,h.                                                   #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    my $x    = int($params->{'x'});
    my $y    = int($params->{'y'});
    my $w    = int($params->{'width'}) || 1;
    my $h    = int($params->{'height'}) || 1;
    my $scrn = $params->{'image'};

    $w  = $self->{'XRES'} if ($w > $self->{'XRES'});
    $h  = $self->{'YRES'} if ($h > $self->{'YRES'});
    $w  = $self->{'XX_CLIP'} - $x if (($x + $w) > $self->{'XX_CLIP'});
    my $scan = $w * $self->{'BYTES'};
    my $WW;
    my $yend = $y + $h;
    if ($yend > $self->{'YY_CLIP'}) {
        $yend = $self->{'YY_CLIP'};
    } elsif ($yend < $self->{'Y_CLIP'}) {
        $yend = $self->{'Y_CLIP'};
    }
    my $WW = int((length($scrn) || 1) / $h);
    my $X_X = ($x + $self->{'XOFFSET'}) * $self->{'BYTES'};
    my ($index,$data,$px,$line,$idx,$px4);

    if (
        ($x >= $self->{'X_CLIP'}) &&
        ($x <= $self->{'XX_CLIP'}) &&
        ($y >= $self->{'Y_CLIP'}) &&
        ($y <= $self->{'YY_CLIP'})
    ) {
        if ($x < 0) {
            $w += $x;
            $x = 0;
        }
        if ($y < 0) {
            $scrn = substr($scrn,(abs($y) * $WW));
            $yend += $y;
            $y = 0;
        }
        $idx = 0;
        $y    += $self->{'YOFFSET'};
        $yend += $self->{'YOFFSET'};
        for($line=$y;$line<$yend;$line++) {
            $index = ($self->{'BYTES_PER_LINE'} * $line) + $X_X;
            switch($self->{'DRAW_MODE'}) {
                case($self->{'NORMAL_MODE'}) {
                    substr($self->{'SCREEN'},$index,$scan) = substr($scrn,$idx,$scan);
                }
                case($self->{'XOR_MODE'}) {
                    substr($self->{'SCREEN'},$index,$scan) ^= substr($scrn,$idx,$scan);
                }
                case($self->{'OR_MODE'}) {
                    substr($self->{'SCREEN'},$index,$scan) |= substr($scrn,$idx,$scan);
                }
                case($self->{'AND_MODE'}) {
                    substr($self->{'SCREEN'},$index,$scan) &= substr($scrn,$idx,$scan);
                }
                case($self->{'MASK_MODE'}) {
                    for($px=0;$px<$w;$px++) {
                        if ($px <= $self->{'XX_CLIP'} && $px >= $self->{'X_CLIP'}) {
                            $px4 = $px * $self->{'BYTES'};
                            $data = substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'});
                            if ($self->{'BITS'} == 32) {
                                if (substr($scrn,($idx+$px4),3).chr(255) ne $self->{'B_COLOR'}) {
                                    substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'}) = substr($scrn,($idx+$px4),$self->{'BYTES'});
                                }
                            } else {
                                if (substr($scrn,($idx+$px4),2) ne $self->{'B_COLOR'}) {
                                    substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'}) = substr($scrn,($idx+$px4),$self->{'BYTES'});
                                }
                            }
                        }
                    }
                }
                case($self->{'UNMASK_MODE'}) {
                    for($px=0;$px<$w;$px++) {
                        if ($px <= $self->{'XX_CLIP'} && $px >= $self->{'X_CLIP'}) {
                            $px4 = $px * $self->{'BYTES'};
                            $data = substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'});
                            if ($self->{'BITS'} == 32) {
                                if (substr($self->{'SCREEN'},($index+$px4),3).chr(255) eq $self->{'B_COLOR'}) {
                                    substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'}) = substr($scrn,($idx+$px4),$self->{'BYTES'});
                                }
                            } else {
                                if (substr($self->{'SCREEN'},($index+$px4),2) eq $self->{'B_COLOR'}) {
                                    substr($self->{'SCREEN'},($index+$px4),$self->{'BYTES'}) = substr($scrn,($idx+$px4),$self->{'BYTES'});
                                }
                            }
                        }
                    }
                }
            }
            $idx += $WW;
        }
    }
}
sub clip_reset {
    ##########################################################
    ##                       CLIP RESET                     ##
    ##########################################################
    # Resets graphics clipping to the full screen            #
    ##########################################################
    my $self = shift;

    $self->{'X_CLIP'}  = 0;
    $self->{'Y_CLIP'}  = 0;
    $self->{'XX_CLIP'} = ($self->{'XRES'} - 1);
    $self->{'YY_CLIP'} = ($self->{'YRES'} - 1);
    $self->{'CLIPPED'} = 0;
}
sub clip_rset {
    my $self   = shift;
    my $params = shift;
    my $x = int($params->{'x'});
    my $y = int($params->{'y'});
    my $w = int($params->{'width'});
    my $h = int($params->{'height'});

    $self->clip_set({'x' => $x,'y' => $y,'xx' => ($x + $w),'yy' => ($y + $h)});
}
sub clip_set {
    ##########################################################
    ##                        CLIP SET                      ##
    ##########################################################
    # Sets the clipping rectangle at top left origin X,Y to  #
    # bottom right location XX,YY.                           #
    ##########################################################
    my $self   = shift;
    my $params = shift;

    $self->{'X_CLIP'}  = int($params->{'x'});
    $self->{'Y_CLIP'}  = int($params->{'y'});
    $self->{'XX_CLIP'} = int($params->{'xx'});
    $self->{'YY_CLIP'} = int($params->{'yy'});

    $self->{'X_CLIP'}  = 0 if ($self->{'X_CLIP'} < 0);
    $self->{'Y_CLIP'}  = 0 if ($self->{'Y_CLIP'} < 0);
    $self->{'XX_CLIP'} = ($self->{'XRES'} - 1) if ($self->{'XX_CLIP'} >= $self->{'XRES'});
    $self->{'YY_CLIP'} = ($self->{'YRES'} - 1) if ($self->{'YY_CLIP'} >= $self->{'YRES'});
    $self->{'CLIPPED'} = 1;
}
sub ttf_print {
    ##############################################################################
    ##                           TRUE-TYPE FONT PRINT                           ##
    ##############################################################################
    # This prints on the screen, a string passed to it in a True Type font.      #
    # The X, Y, Height, and Color are also passed to it.                         #
    #                                                                            #
    # This uses the 'Imager' package.  It allocates a temporary screen buffer    #
    # and prints to it, then this buffer is dumped to the screen at the x,y      #
    # coordinates given.  Since no decent True Type packages or libraries are    #
    # available for Perl, this turned out to be the best and easiest solution.   #
    #                                                                            #
    # Will return the bounding box dimensions instead of printing if $box_mode=1 #
    ##############################################################################
    my $self   = shift;
    my $params = shift;

    my $TTF_x       = int($params->{'x'});
    my $TTF_y       = int($params->{'y'});
    my $TTF_w       = int($params->{'width'});
    my $TTF_h       = int($params->{'height'});
    my $P_color     = $params->{'color'};
    my $text        = $params->{'text'};
    my $face        = $params->{'face'};
    my $box_mode    = int($params->{'bounding_box'} || 0);
    my $center_mode = int($params->{'center'} || 0);
    my $font_path   = $params->{'font_path'};

    my (
        $data,
        $font,
        $neg_width,
        $global_descent,
        $pos_width,
        $global_ascent,
        $descent,
        $ascent,
        $advance_width,
        $right_bearing
    );
    $P_color = substr($P_color,4,2) . substr($P_color,2,2) . substr($P_color,0,2);  # T$        $P_color = Imager::Color->new("#$P_color");

    eval {
        $font = Imager::Font->new(
            'file'  => "$font_path/$face",
            'color' => $P_color,
            'size'  => $TTF_h
        );

        ($neg_width,
            $global_descent,
            $pos_width,
            $global_ascent,
            $descent,
            $ascent,
            $advance_width,
            $right_bearing) = $font->bounding_box('string' => $text,'canon' => 1,'size' => $TTF_h);
        if ($box_mode == 1) {
            return({'width' => $advance_width,'height' => ($global_ascent - $global_descent)});
        } elsif ($center_mode == 1) {
            $TTF_x = int(($self->{'XRES'} - $advance_width) / 2);
            $TTF_y = int((($self->{'YRES'} - $global_ascent) / 2) + $global_ascent);
        }
        $TTF_w = $advance_width;
        my $img = Imager->new(
            'xsize'    => $advance_width, # $TTF_w,
            'ysize'    => (($TTF_h + $global_ascent) - $global_descent), # * 2),
            'channels' => $self->{'BYTES'}
        );

        $img->string(
            'font'  => $font,
            'text'  => $text,
            'x'     => 0,
            'y'     => ($TTF_h - 1),
            'size'  => $TTF_h,
            'color' => $P_color,
            'aa'    => 1
        );

        $img->write(
            'type'          => 'raw',
            'storechannels' => $self->{'BYTES'},
            'interleave'    => 0,
            'data'          => \$data
        );
        $self->blit_write({'x' => $TTF_x,'y' => (($TTF_y - $TTF_h) + 1),'width' => $TTF_w,'height' => (($TTF_h + $global_ascent) - $global_descent),'image' => $data});
    };
    print STDERR $@ if ($@);
    return({'x' => $TTF_x,'y' => $TTF_y-$TTF_h,'width' => $TTF_w,'height' => ($TTF_h + $global_ascent) - $global_descent});
}
sub get_face_name {
    my $self   = shift;
    my $params = shift;

    my $face      = Imager::Font->new(%{$params});
    my $face_name = eval($face->face_name());
    return($face_name);
}
sub load_image {
    my $self   = shift;
    my $params = shift;

    my $img = Imager->new('channels' => 3);
    return() unless ($img->read('file' => $params->{'file'},'allow_incomplete' => 0));
    my $orientation = $img->tags('name' => 'exif_orientation');
    if (defined($orientation) && $orientation) {
        switch($orientation) {
            case(3) { # 180
                $img = $img->rotate('degrees' => 180);
            }
            case(6) { # -90
                $img = $img->rotate('degrees' => 90);
            }
            case(8) { # 90
                $img = $img->rotate('degrees' => -90);
            }
        }
    }
    if ($params->{'adjust'}) {
        $img = $img->convert(
            'matrix' => [
                [ 0,0,1 ],
                [ 0,1,0 ],
                [ 1,0,0 ]
            ]
        );
    }

    $img = $img->convert('preset' => 'addalpha');

    $img->filter('type' => 'autolevels') if ($params->{'autolevels'});

    my ($xs,$ys,$w,$h,%scale);
    $w = int($img->getwidth());
    $h = int($img->getheight());
    if ((defined($params->{'width'}) && $params->{'width'} <=> $w)  || (defined($params->{'height'}) && $params->{'height'} <=> $h)) {
        $scale{'xpixels'} = $params->{'width'} if (defined($params->{'width'}));
        $scale{'ypixels'} = $params->{'height'} if (defined($params->{'height'}));
        $scale{'type'}    = 'min';
        ($xs,$ys,$w,$h) = $img->scale_calculate(%scale);
        $w = int($w);
        $h = int($h);

        $img = $img->scale(%scale);
    }
    $w = int($img->getwidth());
    $h = int($img->getheight());
    my $data = '';
    $img->write(
        'type'          => 'raw',
        'interleave'    => 0,
        'datachannels'  => 4,
        'storechannels' => 4,
        'data'          => \$data
    );

    my ($x,$y);
    if (defined($params->{'x'}) && defined($params->{'y'})) {
        $x = $params->{'x'};
        $y = $params->{'y'};
    } else {
        if ($w < $self->{'XRES'}) {
            $x = ($self->{'XRES'} - $w) / 2;
            $y = 0;
        } elsif ($h < $self->{'YRES'}) {
            $x = 0;
            $y = ($self->{'YRES'} - $h) / 2;
        } else {
            $x = 0;
            $y = 0;
        }
    }
    $x = int($x);
    $y = int($y);

    return({
               'x'           => $x,
               'y'           => $y,
               'width'       => $w,
               'height'      => $h,
               'image'       => $data,
               'orientation' => $orientation
           }
    );
}
sub screen_dump {
    ##############################################################################
    ##                            Dump Screen To File                           ##
    ##############################################################################
    # Dumps the screen to a file as a raw file                                   #
    ##############################################################################
    my $self   = shift;
    my $params = shift;

    my $filename = $params->{'file'};

    my ($w,$h,$dump) = $self->blit_read({'x' => 0,'y' => 0,'width' => $self->{'XRES'},'height' => $self->{'YRES'}});
    open(my $DUMP,'>',$filename);
    print $DUMP $dump;
    close($DUMP);
}
sub RGB_to_16 {
    ##############################################################################
    ##                               RGB to 16 Bit                              ##
    ##############################################################################
    # Converts a 32 bit pixel value to a 16 bit pixel value.                     #
    ##############################################################################
    my $self   = shift;
    my $params = shift;

    my $big_data = $params->{'color'};

    my $n_data;
    while($big_data ne '') {
        my $pixel_data   = substr($big_data,0,3);
        $big_data        = substr($big_data,3) . chr(255);
        my ($b,$g,$r,$a) = unpack('I',$pixel_data);
        $r               = int($r / 8);
        $g               = int($g / 8);
        $b               = int($b / 8);
        my $color        = ($r << 11) + ($g << 6) + $b;
        $n_data         .= pack('S',$color);
    }
    return({'color' => $n_data});
}
sub RGBA_to_16 {
    my $self   = shift;
    my $params = shift;

    my $big_data = $params->{'color'};

    my $n_data;
    while($big_data ne '') {
        my $pixel_data   = substr($big_data,0,4);
        $big_data        = substr($big_data,4);
        my ($b,$g,$r,$a) = unpack('I',$pixel_data);
        $r               = int($r / 8);
        $g               = int($g / 8);
        $b               = int($b / 8);
        my $color        = ($r << 11) + ($g << 6) + $b;
        $n_data         .= pack('S',$color);
    }
    return({'color' => $n_data});
}
sub RGB_to_RGBA {
    my $self   = shift;
    my $params = shift;

    my $big_data = $params->{'color'};
    my $bsize    = length($big_data);
    my $n_data   = chr(255) x (($bsize / 3) * 4);
    my $index    = 0;
    for(my $count=0;$count < $bsize;$count+=3) {
        substr($n_data,$index,3) = substr($big_data,$count+2,1) . substr($big_data,$count+1,1) . substr($big_data,$count,1);
        $index += 4;
    }
    return({'color' => $n_data});
}

## Not objects nor methods, just standard flat subroutines

sub get_info {
    ##########################################################
    ##                    GET IOCTL INFO                    ##
    ##########################################################
    # Used to return an array specific to the ioctl function #
    # NOTE:  It is not object oriented                       #
    ##########################################################
    my $command = shift;
    my $format  = shift;
    my $fb      = shift;
    my $data    = '';
    my @array;
    ioctl($fb,$command,$data);
    @array = unpack($format,$data);
    return(@array);
}
sub set_info {
    ##########################################################
    ##                    GET IOCTL INFO                    ##
    ##########################################################
    # Used to call or set ioctl specific functions           #
    # NOTE:  It is not object oriented                       #
    ##########################################################
    my $command = shift;
    my $format  = shift;
    my $fb      = shift;
    my @array   = @_;
    my $data    = pack($format,@array);
    ioctl($fb,$command,$data);
}

1;

__END__
  
=pod

=head1 NAME

Graphics::Framebuffer

=head1 SYNOPSIS

 use Graphics::Framebuffer;

 my $fb = Graphics::Framebuffer->new();

 $fb->cls();
 $fb->set_color({'red' => 255, 'green' => 255, 'blue' => 255});
 $fb->plot({'x' => 28, 'y' => 79,'pixel_size' => 1});
 $fb->drawto({'x' => 405,'y' => 681,'pixel_size' => 1});
 $fb->circle({'x' => 200, 'y' => 200, 'radius' => 100, 'filled' => 1});

 $fb->close_screen();

=head1 DESCRIPTION

A (mostly) Pure Perl graphics library for exclusive use in a console framebuffer
environment.  It is written for simplicity without the need for complex API's
and drivers.

Back in the old days, computers drew graphics this way, and it was simple and
easy to do.  I was writing a console based media playing program, and was not
satisfied with the limited abilities offered by the Curses library, and I did
not want the overhead of the X environment to get in the way.  My intention
was to create a mobile media server.  In case you are wondering, that project
has been quite successful, and I am still making improvements to it.

There are places where Pure Perl just won't cut it.  So I use the Imager
library to take up the slack.  It's just used to load and save images, and
draw TrueType text.

=head1 AUTHOR

Richard Kelsch <rich@rk-internet.com>

Copyright 2013 Richard Kelsch, All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 VERSION

Version 4.01 (July 21, 2013)

=cut

