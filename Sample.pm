package Finance::Shares::Sample;
use strict;
use warnings;
use Finance::Shares::MySQL;
use Date::Pcalc qw(:all);
use PostScript::Graph::Stock;
use PostScript::Graph::Style;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(ymd_from_string string_from_ymd);
our $VERSION = 0.01;

=head1 NAME

Finance::Shares::Sample - Price data on a single share

=head1 SYNOPSIS

    use Finance::Shares::Simple;
    use Finance::Shares::Simple qw(ymd_from_string
				   string_from_ymd);

=head2 Simplest

Graph a series of stock quotes.

    my $db = new Finance::Shares::MySQL( user => 'me' );
    
    my $s = new Finance::Shares::Sample(
	    mysql	=> $db,
	    epic	=> 'GSK.L',
	    start_date	=> '2002-08-01',
	    end_date	=> '2002-08-31',
	);

    $s->output( 'Glaxo' );

=head2 Typical

Get a series of stock quotes and graph them using specific settings.  Calculate some trend lines from the
Finance::Shares::Sample data and superimpose them on the graph.

    my $psfile = new PostScript::File(
	    landscape => 1,
	    paper => 'A4',
	);
	
    my $s = new Finance::Shares::Sample(
	    mysql => {
		user	 => 'guest',
		password => 'a94Hq',
		database => 'London',
	    },
	    
	    by		 => 'weeks',
	    epic	 => 'GSK.L',
	    start_date	 => '2001-09-01',
	    end_date	 => '2002-08-31'
	);

    my $graph = $s->graph(
	    file	     => $psfile,
	    heading	     => 'GlaxoSmithKline',
	    background	     => [1, 1, 0.9],
	    color	     => [0, 0, 0.8],
	    price_percent    => 50,
	    volume_percent   => 20,
	    analysis_percent => 30,
	    analysis_low     => -100,
	    analysis_high    => 100,
	);

    # construct data for lines
    $graph->add_price_line( $line1, 'Support' );
    $graph->add_volume_line( $line2, 'Average' );
    $graph->add_analysis_line( $line3, 'RSI' );
	
    $s->output( 'Glaxo' );
    
=head1 DESCRIPTION

This module is principally a data structure holding stock quotes.  Price and volume data are held for a particular
share over a specified period.  It is possible to graph the data together with other, user-calculated lines.

All options can be given to the constructor, or to seperate B<fetch> and B<graph> functions.  This module
cooperates closely with Finance::Shares::MySQL and PostScript::Graph::Stock.  See those manpages for further
details.

=head1 CONSTRUCTOR

=cut

sub new {
    my $class = shift;
    my $opt = {};
    if (@_ == 1) { $opt = $_[0]; } else { %$opt = @_; }
    
    my $o = {};
    bless( $o, $class );
    $o->{opt} = $opt;

    ## register database
    if (defined $opt->{mysql}) {
	if (ref($opt->{mysql}) eq 'Finance::Shares::MySQL') {
	    $o->{db} = $opt->{mysql};
	} else {
	    $o->{dir} = $opt->{mysql}{directory};
	    $o->{db} = new Finance::Shares::MySQL( $opt->{mysql} );
	}
    }

    ## option defaults
    $o->{pi2}	 = 2 * atan2(1,1);
    $o->{angeps} = defined($opt->{angle_epsilon}) ? $opt->{angle_epsilon} : 0.05;
    $o->{angdev} = $o->{pi2} * $o->{angeps};
    $o->{prceps} = defined($opt->{price_epsilon}) ? $opt->{price_epsilon} : 0.05;
    $o->{score}  = defined($opt->{threshold})     ? $opt->{threshold}     : 2;
    
    $o->{tries}  = defined($opt->{tries})  ? $opt->{tries}  : 3;
    $o->{dtype}  = defined($opt->{by})     ? $opt->{by}     : 'data';
    $o->{ignore} = defined($opt->{ignore}) ? $opt->{ignore} : 1;
    
    $opt->{dates} = {} unless defined ($opt->{dates});
    my $od = $opt->{dates};
    $od->{show_year} = 0           unless (defined $od->{show_year});
    $od->{by}        = $o->{dtype} unless (defined $od->{by});
    $o->{dtype} = $od->{by};
    
    $o->{seq} = new PostScript::Graph::Sequence;
    
    ## fetch and process data
    $o->fetch($opt->{epic}, $opt->{start_date}, $opt->{end_date}, $opt->{table}) if (defined $opt->{epic});

    return $o;
}

=head2 new( [options] )

C<options> can be a hash ref or a list of hash keys and values (or omitted altogether).  Recognized keys are:

=head3 by

Control how the data are stored.  Suitable values are 'data', 'days', 'workdays', 'weeks', 'months'.  (Default:
'data')

=head3 end_date

The last day of price data, in YYYY-MM-DD format.  Only used if C<epic> is given.  See L<fetch>.
	    
=head3 epic

The market abbreviation for the stock.  The data is fetched from Yahoo, so there probably should be a suffix
indicating the stock exchange (e.g. BSY.L for BSkyB on the London Stock Exchange).  If this is given, the stock
data is fetched, so C<start_date>, C<end_date> and possibly C<table> should also be considered.  See L<fetch>.

=head3 graph

If present, the contents is used in a call to L<new_graph>.  It should be a sub hash containing options suitable
for a PostScript::Graph::Stock object.  See L<PostScript::Graph::Stock,new>.

=head3 mysql

This can be either a reference to a Finance::Shares::MySQL object or a hash ref filled with options for creating one.

Example 1

Using an existing MySQL object.

    my $db = new Finance::Shares::MySQL;	    
    my $ss = new Finance::Shares::Sample (
		mysql => $db,
	    );

Example 2

Creating our own MySQL connection.

    my $ss = new Finance::Shares::Sample (
		mysql => {
		    user     => 'wally',
		    password => '123jiM',
		    database => 'London',
		},
	    );

=head3 start_date

The first day of price data, in YYYY-MM-DD format.  Only used if C<epic> is given.  See L<fetch>.

=head3 table

The MySQL table name for the stock.  Only used if C<epic> is given.  See L<fetch>.

=head3 tries

Specify the number of times an attempt is made to fetch the data from the internet.  (Default: 3)

=cut

sub fetch {
    my $o = shift;

    ## prepare arguments
    my $epic = shift;
    my ($opt, $start, $end, $table) = shift;
    my $tries = $o->{tries};
    if (defined($opt) and ref($opt) eq "HASH") {
	($start, $end, $table) = @_;
	$tries = $opt->{tries} if (defined $opt->{tries});
    } else {
	$start = $opt;
	$opt = $o->{opt}{dates};
	($end, $table) = @_;
    }
    $epic = uc($epic);
    ($table = $epic) =~ s/[^\w]/_/g unless $table;
    $o->{epic}  = $epic;
    $o->{table} = $table;
    $o->{start} = $start;
    $o->{end}   = $end;
    
    ## fetch from database
    my $request = [ [ $epic, $start, $end, $table ], ];
    for my $try (1 .. $tries) {
	my $failed = $o->{db}->fetch_batch( $request );
	last unless ($failed);
    }
    
    $o->{cols} = [qw(Open High Low Close Volume)];
    $o->{rows} = $o->{db}->select_table($table, $o->{cols}, $start, $end);
    $o->prepare_dates($o->{rows}, $opt);
}

=head2 fetch( epic [,opts] [,start [,end [,table]]] )

=over 4

=item C<epic>

The market abbreviation for the stock.  The data is fetched from Yahoo, so there probably should be a suffix
indicating the stock exchange (e.g. BSY.L for BSkyB on the London Stock Exchange).

=item C<opts>

If a hash ref is given here, it should be contain options for filtering dates.  See
L<PostScript::Graph::Stock,prepare_dates>.  Note that this overrides any 'dates' hash given to B<new>.

For convenience, an additional key 'tries' is allowed.  This is the same as (and overrides) the B<new> option of
the same name.

=item C<start>

The first day of price data.  Defaults to the earliest data already fetched (or today's date if none).

=item C<end>

The last day of price data.  Defaults to today's date.

=item C<table>

The name of the MySQL table to use.  By default this is the epic name in upper case with any non-word characters
converted to underscores (e.g. BSY_L if the epic was 'bsy.l').

=back

Three attempts are made to fetch the data from the internet (see L<Finance::Shares::MySQL,fetch_batch>).  Then the
data is extracted from the MySQL database, filtered according to C<opts> then stored as date, price and volume
data.

=cut

sub graph {
    my $o = shift;
    my $opt = {};
    if (@_ == 1) { $opt = $_[0]; } else { %$opt = @_; }

    my $epic = $o->{epic};
    die "No data, call fetch()\nStopped" unless (defined $epic);
    my @date = $o->{end} ? ymd_from_string($o->{end}) : Today();
    my $end_date = Date_to_Text_Long( @date );
    my $dtype = ucfirst($o->{dtype});
    $opt->{heading} = "$epic Shares, $dtype to $end_date";
    $opt->{file}    = {} unless (defined $opt->{file});
    my $of = $opt->{file};
    $of->{landscape} = 1 unless (defined $of->{landscape});
    $of->{errors}    = 1 unless (defined $of->{errors});
    
    $o->{pgs} = new PostScript::Graph::Stock( $opt );
    $o->{pgs}->data_from_sample( $o );

    return $o->{pgs};
}

=head2 graph( [options] )

C<options> can be a hash ref or a list of hash keys and values. It should contain options suitable
for a PostScript::Graph::Stock object, which is returned.  See L<PostScript::Graph::Stock,new>.

Example

    my $sample = new Finance::Shares::Sample(...);
    $sample->fetch( $epic, $start_date, $end_date );
    
    my $graph = $ss->new_graph(...);

    # perhaps add lines to graph
    $graph->add_price_line($data, $style, $key);

    $sample->output( $epic );

For details of constructing the line data see L<PostScript::Graph::Stock,add_price_line>.

Note that the options given here override any given to the constructor.  In particular, it is possible to get into
a mess with the 'dates' or 'by' settings.  The data is filtered for dates when it is fetched according to the
constructor option, 'by'.  Make sure that the 'dates' sub-hash given to B<graph>, if used,
has the same 'by' setting, otherwise there will either be unpredictable gaps in the graph or missing data.

Example

    my $sample = new Finance::Shares::Sample(
	    by => 'days',
	);

    $sample->graph(
	    dates => {
		by => 'days',
	    },
	);

=cut

sub output {
    my ($o, $file, $dir) = @_;
    $dir = $o->{dir} unless (defined $dir);
    
    $o->graph( $o->{opt}{graph} ) unless ($o->{pgs});
    $o->{pgs}->output($file, $dir);
}

=head2 output( file [, dir] )

The graph is constructed and written out to a PostScript file.  A suitable suffix (.ps, .epsi or .epsf) will be
appended to the file name.  This is a convenience method, identical to calling B<output> on the
PostScript::Graph::Stock object returned by B<graph>.  Both these examples do the same thing.

Example 1

    my $ss = new Finance::Shares::Sample(...);
    $ss->fetch( $epic, $start_date, $end_date );
    
    $sg->output( $epic );

Example 2

    my $ss = new Finance::Shares::Sample(
	    ...
	    epic	=> $epic,
	    start_date	=> $start_date,
	    end_date	=> $end_date,
	);

    my $graph = $ss->graph();
    $graph->output();
    
=cut

=head1 SUPPORT METHODS

=cut

sub prepare_dates {
    my $o    = shift;
    my $data = shift;
    my $opt  = {};
    if (@_ == 1) { $opt = $_[0]; } else { %$opt = @_; }

    ## identify date options
    my $dtype = defined($opt->{by}) ? $opt->{by} : "workdays";
    $o->{dtype} = $dtype;
    my ($dsdow, $dsday, $dsmonth, $dsyear, $dsall);
    CASE: {
	if ($dtype eq 'days') {
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (1, 1, 1, 0);
	    last CASE;
	}
	if ($dtype eq 'workdays') {
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (1, 1, 1, 0);
	    last CASE;
	}
	if ($dtype eq 'weeks') {
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (0, 1, 1, 0);
	    last CASE;
	}
	if ($dtype eq 'months') {
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (0, 0, 1, 1);
	    last CASE;
	}
	# ($dtype eq 'data')
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (0, 1, 1, 1);
    }
    $dsdow   = defined($opt->{show_weekday}) ? $opt->{show_weekday}        : $dsdow;
    $dsday   = defined($opt->{show_day})     ? $opt->{show_day}            : $dsday;
    $dsmonth = defined($opt->{show_month})   ? $opt->{show_month}          : $dsmonth;
    $dsyear  = defined($opt->{show_year})    ? $opt->{show_year}           : $dsyear;
    $dsall   = defined($opt->{changes_only}) ? ($opt->{changes_only} == 0) : 0;
    
    my ($daynames, $mthnames);
    my @days   = qw(- Mon Tue Wed Thu Fri Sat Sun);
    my @months = qw(- Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    $daynames  = defined($opt->{days})       ? $opt->{days}		   : \@days;
    $mthnames  = defined($opt->{months})     ? $opt->{months}		   : \@months;
    
    ## remove any headings from data
    my $number = qr/^\s*[-+]?[0-9.]+(?:[Ee][-+]?[0-9.]+)?\s*$/;
    unless ($data->[0][1] =~ $number) {
	my $row = shift(@$data);
    }

    ## extract price and volume
    my (%price, %volume, %order);
    my (@first, @last, $dfirst, $dlast);
    foreach my $row (@$data) {
	my ($date, $open, $high, $low, $close, $volume) = @$row;
	$volume = $open unless (defined $close);
	my @ymd = ($date =~ /(\d{4})-(\d{2})-(\d{2})/);
	unless (@ymd) {
	    @ymd = Decode_Date_EU($date);
	    unless (@ymd) {
		@ymd = Decode_Date_US($date);
	    }
	    $date = string_from_ymd(@ymd) if (@ymd);
	}
	my ($year, $month, $day) = ymd_from_string($date);
	$order{$date}++ if (defined $day);
	$price{$date} = [ $open, $high, $low, $close ] if (defined $close);
	$volume{$date} = $volume if (defined $volume);
	$dfirst = $date, @first = ($year, $month, $day) if (not defined($dfirst) or $date le $dfirst);
	$dlast  = $date, @last  = ($year, $month, $day) if (not defined($dlast)  or $date gt $dlast);
    }

    ## determine number and type of labels
    my ($x, @labels, @dates) = 0;   # $x is index into labels array
    my ($endday, $endlabel, $knownlabel, $knowndate) = (0);
    my @prev = (0, 0, 0);
    my $ldow = 0;
    my ($lday, $lmonth, $lyear) = @prev;
    my ($tdow, $tday, $tmonth, $tyear);
    my ($topen, $tclose, $thigh, $tlow, $tvolume, $total);
    my $ndays  = Delta_Days(@first, @last);
    my $labelmax = 0;
    for (my $i = 0; $i <= $ndays; $i++) {
	my @ymd     = Add_Delta_Days(@first, $i);
	my $dow     = Day_of_Week(@ymd);
	my $weekday = ($dow >= 1 and $dow <= 5);
	my $date    = string_from_ymd(@ymd);
	my $known   = $order{$date};
	my $pdata   = $price{$date};
	
	## construct label
	my ($year, $month, $day) = @ymd;
	my $label = "";
	$label .= $daynames->[$dow] . " "   if ($dsdow   and ($dsall or ($dow != $ldow)));
	$label .= $day . " "                if ($dsday   and ($dsall or ($day != $lday)));
	$label .= $mthnames->[$month] . " " if ($dsmonth and ($dsall or ($month != $lmonth)));
	$label .= $year . " "               if ($dsyear  and ($dsall or ($year != $lyear)));
	$label =~ s/\s+$//;
	$labelmax = length($label) if (length($label) > $labelmax);

	## select dates
	CASE: {
	    ## every day
	    if ($dtype eq 'days') {
		if ($known) {
		    $order{$date} = $x; push @dates, $date;
		    push @labels, $label; 
		    $ldow=$dow; $lday=$day; $lmonth=$month; $lyear=$year;
		} else {
		    delete $order{$date};
		    push @labels, ""; 
		}
		$x++;
		last CASE;
	    }
	    
	    ## every workday
	    if ($dtype eq 'workdays') {
		if ($weekday) {
		    if ($known) {
			$order{$date} = $x; push @dates, $date;
			push @labels, $label; 
			$ldow=$dow; $lday=$day; $lmonth=$month; $lyear=$year;
		    } else {
			delete $order{$date};
			push @labels, ""; 
		    }
		    $x++;
		}
		last CASE;
	    }
	    
	    ## every week
	    if ($dtype eq 'weeks') {
		# Each weeks data accumulates until the next week begins.
		# So at the start of each week, the previous week's data are
		# recorded under the last recorded weekday (usually Friday).
		if ($weekday) {
		    # $dow: 1=Monday .. 7=Sunday
		    if ($dow >= $endday) { 
			if ($known) {
			    # add values to totals for week
			    $total++;
			    $topen   += $pdata->[0];
			    $thigh   += $pdata->[1];
			    $tlow    += $pdata->[2];
			    $tclose  += $pdata->[3];
			    $tvolume += $volume{$date};
			    # remove days data
			    delete $order{$date};
			    delete $price{$date};
			    delete $volume{$date};
			    # note this as last date known so far
			    $knowndate = $date; $knownlabel = $label;
			} else {
			    # keep track of last date in case week has no data at all
			    $endlabel = $label;
			}
			$tdow=$dow; $tday=$day; $tmonth=$month; $tyear=$year;
		    } else {
			# Monday
			if (defined $knowndate) { 
			    # put last weeks totals into last known date
			    $price{$knowndate} = [ $topen/$total, $thigh/$total, $tlow/$total, $tclose/$total ];
			    $volume{$knowndate} = $tvolume/$total;
			    $order{$knowndate} = $x; 
			    push @dates, $knowndate; 
			    $endlabel = $knownlabel;
			}
			$x++;
			push @labels, $endlabel;
			$labelmax = length($endlabel) if (length($endlabel) > $labelmax);
			# remember this for relative labels
			$ldow=$tdow; $lday=$tday; $lmonth=$tmonth; $lyear=$tyear;
			# clear for a new week
			if ($known) {
			    $total   = 1;
			    $topen   = $pdata->[0];
			    $thigh   = $pdata->[1];
			    $tlow    = $pdata->[2];
			    $tclose  = $pdata->[3];
			    $tvolume = $volume{$date};
			    # remove days data
			    delete $order{$date};
			    delete $price{$date};
			    delete $volume{$date};
			} else {
			    $topen = $thigh = $tlow = $tclose = $tvolume = $total = 0;
			}
			$endlabel = $label;
			$knowndate  = undef;
		    }
		    $endday = $dow;
		}
		last CASE;
	    }

	    ## every month
	    if ($dtype eq 'months') {
		# Each months data accumulates until the next month begins.
		if ($weekday) {
		    if ($day >= $endday) {
			if ($known) {
			    $total++;
			    $topen   += $pdata->[0];
			    $thigh   += $pdata->[1];
			    $tlow    += $pdata->[2];
			    $tclose  += $pdata->[3];
			    delete $price{$date};
			    delete $volume{$date};
			    $knowndate = $date; $knownlabel = $label;
			} else {
			    $endlabel = $label;
			}
			$tdow=$dow; $tday=$day; $tmonth=$month; $tyear=$year;
		    } else {
			# 1st working day of new month
			if (defined $knowndate) { 
			    $price{$knowndate} = [ $topen/$total, $thigh/$total, $tlow/$total, $tclose/$total ];
			    $order{$knowndate} = $x; 
			    push @dates, $knowndate; 
			    $endlabel = $knownlabel;
			}
			$x++;
			push @labels, $endlabel;
			$labelmax = length($endlabel) if (length($endlabel) > $labelmax);
			$ldow=$tdow; $lday=$tday; $lmonth=$tmonth; $lyear=$tyear;
			# start a new month
			if ($known) {
			    $total   = 1;
			    $topen   = $pdata->[0];
			    $thigh   = $pdata->[1];
			    $tlow    = $pdata->[2];
			    $tclose  = $pdata->[3];
			    delete $price{$date};
			    delete $volume{$date};
			} else {
			    $topen = $thigh = $tlow = $tclose = $tvolume = $total = 0;
			}
			$endlabel = $label;
			$knowndate  = undef;
		    }
		    $endday = $day;
		}
		last CASE;
	    }

	    ## dates given
	    #  ($dtype eq 'data')
	    if ($known) {
		$order{$date} = $x; push @dates, $date; 
		$x++;
		push @labels, $label; 
		$ldow=$dow; $lday=$day; $lmonth=$month; $lyear=$year;
	    }
	}
    }

    ## finish off
    if (defined $knowndate) { 
	$price{$knowndate} = [ $topen/$total, $thigh/$total, $tlow/$total, $tclose/$total ];
	$volume{$knowndate} = $tvolume/$total unless ($dtype eq 'months');
	$order{$knowndate} = $x; 
	push @dates, $knowndate; 
	$endlabel = $knownlabel;
    }
    if (defined $endlabel) {
	push @labels, $endlabel;
	$labelmax = length($endlabel) if (length($endlabel) > $labelmax);
    }
 
    $o->{order}  = \%order;
    $o->{price}  = \%price;
    $o->{volume} = \%volume;
    $o->{dates}  = \@dates;
    $o->{labels} = \@labels;
    $o->{lblmax} = $labelmax; 
}

=head2 prepare_dates( data [,options] )

This splits raw CSV-style data into the date labels, prices and volumes needed for a stock graph.
C<data> should be a reference to an array of arrays.  The inner arrays should hold a date in YYYY-MM-DD format,
opening, high, low and closing prices followed by the volume.  Either the prices or the volume may be omitted. 

Example

    $data = [
    [2001-06-01,454.50,475.00,448.50,461.00,8535680],
    [2001-06-04,465.00,465.00,458.50,459.00,3254045],
    [2001-06-05,458.25,464.00,455.00,462.00,4615016],
    ];

C<options> may either be a hashref or a list of hash keys and values.  Recognized hash keys follow.

=head3 by

This string determines how the dates are distributed across the X axis.

=over 4

=item B<data>

The dates are those present in the data, in chronological order (the default).

=item B<days>

Every day between the first and last day is listed, whether there is data for that day or not.

=item B<workdays>

Every day except Saturdays and Sundays.  Occasional holidays are ignored, just showing as days with no data.

=item B<weeks>

Only the data for last trading day of each week is presented.  No attempt is made to take the rest of the week
into account - those days are just hidden.   If any trading is recorded for that week, the latest day is given; if
not the last working day is shown, with no data.

=item B<months>

As weeks, but showing the last trading day of each month.

=back

=head3 changes_only

The date labels are made up of weekday, day, month and year.  Which sections are shown by default depends on the
B<dates> setting.  If this is 1, each part is only shown if it has changed from the previous label.  If 0, all the
selected parts are shown.  (Default: 1)

=head3 days

This allows the weekday abbreviations to be presented in a different language.  It should be an array ref
containing strings.  Monday = 1, so there should probably be a dummy string for 0.  (Defaults to English).

=head3 months

This allows the month abbreviations to be presented in a different language.  It should be an array ref
containing strings.  January = 1, so there should probably be a dummy string for 0.  (Defaults to English).

=head3 show_day

Show the date of day within the month.  (Default: depends on C<dates>)

=head3 show_month

Show the month.  (Default: depends on C<dates>)

=head3 show_weekday

Show the day of the week.  (Default: depends on C<dates>)

=head3 show_year

Show the month.  (Default: depends on C<dates>)

=head3 Values returned

=over 4

=item C<order>

A hash ref.  Keyed by date, the integer values indicate the order of labelled dates.  Used for locating valid
dates within the dates array.

=item C<price>

A hash ref.  Keyed by the YYYY-MM-DD date, each entry points to a list of price data.

    [ Open, High, Low, Close ]

=item C<volume>

A hash ref.  If present the Volume (or averaged volume) of trades is keyed by the YYYY-MM-DD date.

=item C<dates>

An array ref.  Each date in this list (in YYYY-MM-DD format) represents a labelled point on the graph - typically
a day, week or month.   However, not all of these may be visible as labels if there is not enough room across the
axis.  This should be the 'X' value used in constructing all superimposed lines.

=item C<labels>

An array ref.  The labels to be printed.

=item C<labelmax>

The length of the longest label.

=back

=cut

=head1 EXPORTED FUNCTIONS

No export tags are defined and no functions are exported by default.  The functions defined here must be specified
by name before it can be used.

    use Finance::Shares::Sample qw(ymd_from_string
				   string_from_ymd);

=cut

sub ymd_from_string {
    my $date = shift;
    return ($date =~ /(\d{4})-(\d{2})-(\d{2})/);
}

=head2 ymd_from_string( date )

Takes a string in the form YYYY-MM-DD and returns an array of integers (year, month, day).

=cut

sub string_from_ymd {
    return sprintf("%04d-%02d-%02d", @_);
}

=head2 string from_ymd( year, month, day )

Converts the three integer values into a YYYY-MM-DD string.

=cut

=head1 BUGS

Please report those you find to the author.

=head1 AUTHOR

Chris Willmot, chris@willmot.org.uk

=head1 SEE ALSO

L<Finance::Shares::Log>,
L<Finance::Shares::MySQL> and
L<PostScript::Graph::Stock>.

=cut

1;
