# Oxford University calendar conversion.
# Simon Cozens (c) 1999-2002
# Eugene van der Pijll (c) 2004
# Dominic Hargreaves / University of Oxford (c) 2007
# Artistic License
package Oxford::Calendar;
$Oxford::Calendar::VERSION = "1.9";
use strict;
use Text::Abbrev;
use Date::Calc qw(Add_Delta_Days Decode_Date_EU Delta_Days Mktime);
use YAML;
use Time::Seconds;

use constant CALENDAR => '/etc/oxford-calendar.yaml';
use constant SEVEN_WEEKS => 7 * ONE_WEEK;
use constant DEFAULT_MODE => 'nearest';

=head1 NAME

Oxford::Calendar - University of Oxford calendar conversion routines

=head1 SYNOPSIS

    use Oxford::Calendar;
    print "Today is ", Oxford::Calendar::ToOx(reverse Date::Calc::Today);

=head1 DESCRIPTION

This module converts University of Oxford dates to and from Real World
dates using data supplied in YAML format.

If the file F</etc/oxford-calendar.yaml> exists, data will be read from that;
otherwise, built-in data will be used. The built-in data is periodically
updated from the authoritative source at

L<http://www.ox.ac.uk/about_the_university/university_year/dates_of_term.html>.

=head1 DATE FORMAT

An Oxford academic date takes the form

=over

<day of week>, <week number>[st,nd,rd,th] week, <term name> <year>

=back

where term name is one of

=over

=item *

Michaelmas (autumn)

=item *

Hilary (spring)

=item *

Trinity (summer)

=back

Example:

Friday, 8th Week, Michaelmas 2007

L<http://www.ox.ac.uk/about_the_university/university_year/index.html>
describes the academic year at Oxford.

=cut

our %db;

my $_initcal;    # If this is true, we have our database of dates already.
my @_oxford_terms;
my @_days = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);

sub _get_week_suffix {
    my $week = shift;
    die "_get_week_suffix: No week given" unless defined $week;
    my $wsuffix = "th";
    abs($week) == 1 && ( $wsuffix = "st" );
    abs($week) == 2 && ( $wsuffix = "nd" );
    abs($week) == 3 && ( $wsuffix = "rd" );
  
    return $wsuffix;
}

sub _find_week {
    my $tm = shift;
    my $sweek = shift;
    my $sweek_tm = shift;

    my $max_week = shift;
    my $max_tm = shift;

    my $eow = $sweek_tm + ONE_WEEK;

    while ( $tm >= $eow ) {
        $eow += ONE_WEEK;
        $sweek++;
    }
    # Sanity Check
    die "_find_week: $sweek is longer than max weeks ($max_week)"
        if ( $sweek >= $max_week );

    die "_find_week: $eow is after the end of term ($max_tm)"
        if ( $eow > $max_tm);
   
    return $sweek;
}

sub _init_db {
    my $db;
    if ( -r CALENDAR ) {
        $db = YAML::LoadFile(CALENDAR);
    }
    else {
        my $data = join '', <DATA>;
        $db = YAML::Load($data);
    }
    %db = %{ $db->{Calendar} };
}

sub _init_range {
    foreach my $termspec ( keys %db ) {
        next unless $db{$termspec};

        my $time = eval { Mktime( Decode_Date_EU( $db{$termspec} ), 0, 0, 0 ) }
             or die
                "Could not decode date ($db{$termspec}) for term $termspec: $@";

        push @_oxford_terms,
            [$time, ($time + SEVEN_WEEKS), split(/ /, $termspec)];
    }

    # Sort this here, but do not rely on it later
    @_oxford_terms = sort { $a->[0] <=> $b->[0] } @_oxford_terms;
}

sub _fmt_oxdate_as_string {
    my ( $dow, $week, @term ) = @_;
    my $wsuffix = _get_week_suffix($week);
    return "$_days[$dow], $week$wsuffix week, $term[2] $term[3].";
}

sub Init {
    _init_db;
    _init_range;
    $_initcal++;
}

=head1 FUNCTIONS

=over 3

=item ToOx($day, $month, $year, [\%options])

Given a day, month and year in standard human format (that is, month is
1-12, not 0-11, and year is four digits) will return a string of the
form

    Day, xth week, Term year.

or an array

    (Day, week of term, Term, year)
    
depending on how it is called. The exact behaviour is modified by the 'mode'
option described below.

If no data is available for the requested date, undef will be returned.

%options can contain additional named parameter options:

=over 4

=item mode

Several modes are available:

=over 5

=item full_term

Term dates will only be returned if the date requested is part of a full
term (as defined by the web page above).

=item ext_term

Term dates will only be returned if the date requested is part of an extended
term (roughly as defined by the web page above).

=item nearest

Will return term dates based on the nearest term, even if the date requested
is not part of a valid term (ie will include fictonal week numbers).

This is currently the default behaviour, for backwards compatibility with
previous releases; this may be changed in future.

=back

=back

=cut

sub ToOx {
    my (@dmy, $options);
    ($dmy[0], $dmy[1], $dmy[2], $options) = @_;
    my $mode = $options->{mode} || DEFAULT_MODE;
    my ($week, @term);
    Init unless defined $_initcal;
    my $tm = Mktime((reverse @dmy), 0, 0, 0);
    my $dow = (localtime($tm))[6];

    # Try full_term
    @term = ThisTerm(@dmy);
    if ( $#term ) {
        # We're in full term
        $week = _find_week($tm, 1, $term[0], 9, $term[1] + ONE_WEEK);
        return ($_days[$dow], $week, $term[2], $term[3]) if ( wantarray );
        return _fmt_oxdate_as_string( $dow, $week, @term );
    } else {
        return undef if $mode eq 'full_term';
        # Try ext_term
        foreach my $ar ( sort { $a->[0] <=> $b->[0] } @_oxford_terms ) {
            if ( $tm >= ( $ar->[0] - 3 * ONE_WEEK ) &&
                 $tm <  (  $ar->[1] + 3 * ONE_WEEK) )  {
                @term = @{$ar};
                last;
            }
        }
        if ( $#term ) {
            $week = _find_week($tm, -2, ($term[0] - 3 * ONE_WEEK), 11,
                $term[1] + 3 * ONE_WEEK);

            return ($_days[$dow], $week, $term[2], $term[3]) if ( wantarray );
            return _fmt_oxdate_as_string( $dow, $week, @term );
        } else {
            return undef if $mode eq 'ext_term';
            # Try nearest
            my @terms = sort { $a->[0] <=> $b->[0] } @_oxford_terms;
            my($prevterm,$nextterm);
            my $curterm = shift @terms;

            while ($curterm) { 
                if ( $tm < $curterm->[0] ) {
                    if ( $prevterm && $tm >= ($prevterm->[1] + ONE_WEEK) ) {
                        $nextterm = $curterm;
                        last;
                    } else {
                        return undef; # out of range 
                    }
                } 
                $prevterm = $curterm;
                $curterm = shift @terms;
            }
            return undef unless $nextterm;

            # We are in the gap between terms .. which one is closest?
            my $prevgap = $tm - ($prevterm->[1] + ONE_WEEK);
            my $nextgap = $tm - $nextterm->[0];

            if ( abs($prevgap) < abs($nextgap) ) {
                # if equal go for -<n>th week
                my $max_weeks = 8 + int( ($nextterm->[0] - $prevterm->[1]) / (24 * 60 * 60 * 7) );
                $week = _find_week($tm, 8, $prevterm->[1], $max_weeks, $nextterm->[0]);
                @term = @{$prevterm};
            } else {
                my $delta = $nextgap / (24 * 60 * 60);
                $week = 1 + int( $delta / 7 );
                $week -= 1 if $delta % 7;
                @term = @{$nextterm};
            }

            return ($_days[$dow], $week, $term[2], $term[3]) if ( wantarray );
            return _fmt_oxdate_as_string( $dow, $week, @term );
        }
    }
}

=item ThisTerm($day, $month, $year)

Given a day, month and year in standard human format (that is, month is
1-12, not 0-11, and year is four digits) will returns the current term
or undef if in vacation or unknown.. The term is either a string or
(term, year) depending on context.

=cut

sub ThisTerm {
   Init unless defined $_initcal;

   my @dmy = @_;
   my $tm;
   if ( $#dmy ) {
       $tm = Mktime( (reverse @dmy), 0,0,0)
   } else {
       $tm = time()
   }

   foreach my $ar ( sort { $a->[0] <=> $b->[0] } @_oxford_terms ) {
       return wantarray ? @$ar : "$ar->[2] $ar->[3]"
           if ( $tm >= $ar->[0] && $tm < ($ar->[1] + ONE_WEEK) );
       last if $tm <= $ar->[0]; # there is no point carrying on if we reach here
   }

   return undef;
}

=item NextTerm($day, $month, $year)

Given a day, month and year in standard human format (that is, month is
1-12, not 0-11, and year is four digits) will returns the next term (if
this is is known to the module) or undef. The term is either a string or
(term, year) depending on context.

=cut

sub NextTerm {
   Init unless defined $_initcal;

   my @dmy = @_;
   my $tm;
   if ( $#dmy ) {
       $tm = Mktime( (reverse @dmy), 0,0,0)
   }
   else {
       $tm = time()
   }

   my @tterms = sort { $a->[0] <=> $b->[0] } @_oxford_terms;
   my $tdata = shift @tterms;
   while ( $tdata ) {
       my $eot = $tdata->[1] + ONE_WEEK;
       my $next = shift @tterms;

       # It is easy if we are within a term
       if ( $tm >= $tdata->[0] && $tm <= $eot ) {
           return wantarray ?  @$next : "$next->[2] $next->[3]";
       }

       if ( $tm < $tdata->[0] ) { # Vacation time
           return wantarray ?  @$tdata : "$tdata->[2] $tdata->[3]";
       }

       $tdata = $next;
   }

   return undef;
}

=item Parse($string)

Takes a free-form description of an Oxford calendar date, and attempts
to divine the expected meaning. If the name of a term is not found, the
current term will be assumed. If the description is unparsable, the text
C<"UNPARSABLE"> is returned.  Otherwise, output is of the form
C<($year,$term,$week,$day)>

This function is experimental.

=cut

sub Parse {
    my $string = shift;
    my $term   = "";
    my ( $day, $week, $year );
    $day = $week = $year = "";

    $string = lc($string);
    $string =~ s/week//g;
    my @terms = qw(Michaelmas Hilary Trinity);
    $string =~ s/(\d+)(?:rd|st|nd|th)/$1/;
    my %ab = Text::Abbrev::abbrev( @_days, @terms );
    my $expand;
    while ( $string =~ s/((?:\d|-)\d*)/ / ) {
        if ( $1 > 50 ) { $year = $1; $year += 1900 if $year < 1900; }
        else { $week = $1 }
    }
    foreach ( sort { length $b <=> length $a } keys %ab ) {
        if ( $string =~ s/\b$_\w+//i ) {

            #pos($string)-=length($_);
            #my $foo=lc($_); $string=~s/\G$foo[a-z]*/ /i;
            $expand = $ab{$_};
            $term   = $expand if ( scalar( grep /$expand/, @terms ) > 0 );
            $day    = $expand if ( scalar( grep /$expand/, @_days ) > 0 );
        }
    }
    unless ($day) {
        %ab = Text::Abbrev::abbrev(@_days);
        foreach ( sort { length $b <=> length $a } keys %ab ) {
            if ( $string =~ /$_/ig ) {
                pos($string) -= length($_);
                my $foo = lc($_);
                $string =~ s/\G$foo[a-z]*/ /;
                $day = $ab{$_};
            }
        }
    }
    unless ($term) {
        %ab = Text::Abbrev::abbrev(@terms);
        foreach ( sort { length $b <=> length $a } keys %ab ) {
            if ( $string =~ /$_/ig ) {
                pos($string) -= length($_);
                my $foo = lc($_);
                $string =~ s/\G$foo[a-z]*/ /;
                $term = $ab{$_};
            }
        }
    }

    # Assume this term?
    unless ($term) {
        $term = ToOx( reverse Date::Calc::Today() );
        return "Can't work out what term" unless $term =~ /week/;
        $term =~ s/.*eek,\s+(\w+).*/$1/;
    }
    $year = ( Date::Calc::Today() )[0] unless $year;
    return "UNPARSABLE" unless defined $week and defined $day;
    return ( $year, $term, $week, $day );
}

=item FromOx($year, $term, $week, $day)

Converts an Oxford date into a Georgian date, returning a string of the
form C<DD/MM/YYYY> or an error message.

=cut

sub FromOx {
    my %lu;
    Init unless defined $_initcal;
    my ( $year, $term, $week, $day );
    ( $year, $term, $week, $day ) = @_;
    $year =~ s/\s//g;
    $term =~ s/\s//g;
    return "Out of range " unless exists $db{"$term $year"};
    {
        my $foo = 0;
        %lu = ( map { $_, $foo++ } @_days );
    }
    my $delta = 7 * ( $week - 1 ) + $lu{$day};
    my @start = Date::Calc::Decode_Date_EU( $db{"$term $year"} );
    return "The internal database is bad for $term $year"
        unless $start[0];
    return join "/", reverse( Date::Calc::Add_Delta_Days( @start, $delta ) );

}

=item GetOxfordTerms

Returns a reference to an array containing a reference to an array for each
term known about in the database; each inner array contains the unixtime of
midnight on Sunday of 1st Week, the unixtime of midnight on Sunday of 8th
week, the term name, and the year.

=cut

sub GetOxfordTerms {
    Init unless defined $_initcal;
    \@_oxford_terms;
}

"A TRUE VALUE";

=head1 AUTHOR

Simon Cozens is the original author of this module.

Eugene van der Pijll, C<pijll@cpan.org> took over maintenance from
Simon for a time.

Dominic Hargreaves currently maintains this module in his capacity as
employee of the Computing Services, University of Oxford.

=cut

__DATA__
--- #YAML:1.0
Calendar:
  Hilary 2001: 14/01/2001
  Hilary 2002: 13/01/2002
  Hilary 2003: 19/01/2003
  Hilary 2004: 18/01/2004
  Hilary 2005: 16/01/2005
  Hilary 2006: 15/01/2006
  Hilary 2007: 14/01/2007
  Hilary 2008: 13/01/2008
  Hilary 2009: 18/01/2009
  Hilary 2010: 17/01/2010
  Hilary 2011: 16/01/2011
  Hilary 2012: 15/01/2012
  Hilary 2013: 13/01/2013
  Michaelmas 2001: 07/10/2001
  Michaelmas 2002: 13/10/2002
  Michaelmas 2003: 12/10/2003
  Michaelmas 2004: 10/10/2004
  Michaelmas 2005: 09/10/2005
  Michaelmas 2006: 08/10/2006
  Michaelmas 2007: 07/10/2007
  Michaelmas 2008: 12/10/2008
  Michaelmas 2009: 11/10/2009
  Michaelmas 2010: 10/10/2010
  Michaelmas 2011: 09/10/2011
  Michaelmas 2012: 07/10/2012
  Trinity 2001: 22/04/2001
  Trinity 2002: 21/04/2002
  Trinity 2003: 27/04/2003
  Trinity 2004: 25/04/2004
  Trinity 2005: 24/04/2005
  Trinity 2006: 23/04/2006
  Trinity 2007: 22/04/2007
  Trinity 2008: 20/04/2008
  Trinity 2009: 26/04/2009
  Trinity 2010: 25/04/2010
  Trinity 2011: 01/05/2011
  Trinity 2012: 22/04/2012
  Trinity 2013: 21/04/2013
