package Finance::Shares::Sample;
use strict;
use warnings;
use fields;
use Carp;
use Text::CSV_XS;
use Date::Pcalc qw(:all);
use PostScript::File qw(check_file);
use PostScript::Graph::Stock;
use PostScript::Graph::Style;
use Finance::Shares::Log qw(ymd_from_string string_from_ymd);
use Finance::Shares::MySQL;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(%linefunc %bandfunc %timefunc %evalfunc line_key);
our $VERSION = 0.02;

# Pseudohash keys for plines, vlines and alines entries
our @line_fields = qw(data style key show);

# All Finance::Shares::Sample test and line generating functions
# provided by other modules must register here as key => fn ref.
our %linefunc;	    # build line data sets;	args= (sample, strict, show, chart, period, style)
our %bandfunc;	    # build bounds around line; args= (sample, strict, show, chart, func, period, band_arg, style)
our %timefunc;	    # get period from params;	args= (strict, period, band_arg)
our %evalfunc;	    # get value for a date;	args= (sample, chart, date, func, param)

our %pricepos = (
	line_key('price','open')  => 0,
	line_key('price','high')  => 1,
	line_key('price','low')   => 2,
	line_key('price','close') => 3,
    );

=head1 NAME

Finance::Shares::Sample - Price data on a single share

=head1 SYNOPSIS

    use Finance::Shares::Simple;
    use Finance::Shares::Simple qw(ymd_from_string
				   string_from_ymd);

=head2 Simplest

Graph a series of stock quotes.

    my $ss = new Finance::Shares::Sample(
		source	    => 'gsk,csv',
		epic  => 'GSK.L',
	    );

    $ss->output( 'Glaxo' );

=head2 Typical

Get a series of stock quotes and graph them using specific settings.  Calculate some trend lines from the
Finance::Shares::Sample data and superimpose them on the graph.

    my $s = new Finance::Shares::Sample(
	    source => {
		user	 => 'guest',
		password => 'a94Hq',
		database => 'London',
	    },
	    
	    dates_by   => 'weeks',
	    epic => 'GSK.L',
	    start_date => '2001-09-01',
	    end_date   => '2002-08-31'

	    graph => {
		file => {
		    landscape => 1,
		    paper => 'A4',
		},
		heading	   => 'GlaxoSmithKline',
		background => [1, 1, 0.9],
		color	   => [0, 0, 0.8],
		
		price => {
		    percent => 50,
		},
		
		analysis => {
		    percent => 30,
		    low	    => -100,
		    high    => 100,
		},
		
		volume => {
		    percent => 20,
		},
	    },

	    lines => {
		color => [1, 0, 0],
	    },
	);

    # construct data for lines, and then...
    $graph->add_price_line( $line1, 'Support' );
    $graph->add_volume_line( $line2, 'Average' );
    $graph->add_analysis_line( $line3, 'RSI' );
	
    $s->output( 'Glaxo' );
    
=head1 DESCRIPTION

This module is principally a data structure holding stock quotes.  Price and volume data are held for a particular
share over a specified period.  This data can be read from a CSV file or from an array, but more usually it is
fetched from Finance::Shares::MySQL which in turn handles getting the data from the internet.

Facilities are provided to graph the data together with other, user-calculated lines.

All options can be given to the constructor, or to seperate B<fetch> and B<graph> functions.  This module
cooperates closely with Finance::Shares::MySQL and PostScript::Graph::Stock.  See those manpages for further
details.

=head2 The Data

This object is used as a data structure common to a number of modules.  Therefore, unusually, most of the internal
data is made available directly.  The hash and array refs documented here can be relied upon to exist as soon as the
object has been constructed, although C<dates>, C<prices> and C<volumes> are by far the most useful.  Other values
are made available for reading, but changing them will probably cause chaos.

=head3 alines

An array of all data sets derived for the analysis chart section.  See L<plines>.

=head3 dates

An array ref indicating a list of dates in YYYY-MM-DD format.  These are the dates of all known data points.  If
any prices exist, there should be one for each date.  If any volumes exist, there should be one for each date.

=head3 dtype

The value given to 'dates_by' (etc.) controlling how the data is distributed.  One of 'days', 'weekdays',
'alldays', 'weeks', 'months'.

=head3 idx

A hash ref acting as an index into the C<dates>, C<prices> or C<volumes> arrays.

    my $s = new Finance::Shares::Sample(...);
    
    my $i = $s->{idx}{'2002-09-01'};
    my $closing_price = $s->{prices}[$i];

This is the same as the following:

    my $closing_price = $s->{price}{'2002-09-01'}[3];

The first method would be best for comparing closing prices with the days before and after, while the second would
be better to compare the closing price with the highest of the day.
    
=head3 labels

An array ref indicating a label for each line across a PostScript::Graph::Stock chart.  Some of these labels may
be blank (or a single space) if there is too little room to show them all.  Not every label has data associated
with it e.g. weekends when 'days' are specified.

=head3 lblmax

A scalar holding the length of the longest label.  Used by PostScript::Graph::Stock.

=head3 order

A hash ref.  Keyed by YYYY-MM-DD dates, there is an entry for each C<date> known.  The value is the label number.
Used to convert dates to points on a PostScript::Graph::Stock chart.

=head3 plines

An array of all data sets derived from the prices.  Each entry is a pseudo-hash with the following keys:

=over 8

=item data

An array ref similar to C<prices> or C<volumes>.

=item style

Either a PostScript::Graph::Style object or a hash ref holding options for one.

=item key

The string to be shown next to the style in the chart's Key.

=item show

True if to be drawn, false otherwise.

=item func

String identifying the function creating the data.

=item params

Any parameters passed to C<func> which are needed to uniquely identify the line.

=back

=head3 price

A hash ref.  Keyed by YYYY-MM-DD dates, the values are array refs indicating (open, high, low, close) prices.

Note that some of the entries here may be aggregates.  For example, when processing the data by 'weeks', Friday's
values are over-written with the week's averages.  The C<closes> array should be used when analysing price data.
These values are held for plotting each days' spread on a PostScript::Graph::Stock chart.

=head3 prices

An array ref indicating the closing price (if any) for every C<date> known.  This is the data that should be
processed when analysing price movement.  Each entry has the form:

    [ 'YYYY-MM-DD', price ]

=head3 vlines

An array of all data sets derived from the volume data.  See L<plines>.

=head3 volume

A hash ref keyed by YYYY-MM-DD dates and used while preparing the data (See C<price>).  Use the C<volumes> array
when analysing volume data.

=head3 volumes

An array ref.  If volume data was read in there should be a value here corresponding with each date in the
C<dates> array.  Each entry has the form:

    [ 'YYYY-MM-DD', volume ]

=head2 Managing Styles

Often the data will be output as a graph in PostScript format.  The PostScript::Graph::Stock object used for this
provides facilities ensuring that each line drawn on each chart is different from the previous one.

Lines can be given styles directly.  See L<PostScript::Graph::Style> for details.  However each graph also has
a PostScript::Graph::Sequence which is used unless the style option C<auto => 'none'> is given.  How the styles
vary can be altered in two ways.  It is possible to change the order of change using B<auto> or the values of the
settings themselves using B<setup>.

B<Example 1>

    my $sample = new Finance::Shares::Sample(
	    price_lines => {
		line	=> {},
	    },
	);
    my $graph = $sample->graph();
    my $sequence = $graph->price_sequence();
    
    $sequence->setup( 'red',   [1, 0.75, 0.5] );
    $sequence->setup( 'green', [0.4, 0.8] );
    $sequence->setup( 'blue', [0.1] );
    $sequence->auto( 'green', 'red', 'blue' );

    # prepare line data
    $sample->add_price_line($data1, 'One');
    $sample->add_price_line($data2, 'Two');
    $sample->add_price_line($data3, 'Three');
    $sample->add_price_line($data4, 'Four');
    
    $sample->output( 'graph' );

The four lines added to the price chart will be in various shades of orange.  There are a few things to notice
about this example.

=over 4

=item B<*>

The order is important.  The sequence settings must be made before any lines are added.

=item B<*>

Six colours are generated in this sequence, all combinations of 3 red and 2 green.  If more than six lines were
drawn, the styles would be repeated.

=item B<*>

The green settings vary fastest.  The colours generated would be, in order:

    Red	    Green   Blue
    1.0	    0.4	    0.1
    1.0	    0.8	    0.1
    0.75    0.4	    0.1
    0.75    0.8	    0.1
    0.5	    0.4	    0.1
    0.5	    0.8	    0.1

=item B<*>

There is no need to specify a style provided both lines and points are wanted.  In fact, there is no need to
specify the sequence data either.  However, the defaults assume a minimal black and white printer.

If a hash of style options is given to each line, remember to set up line and/or point sub-hashes, even if they
are empty.  It is the presence of these sub-hashes which determines whether each gets drawn.  In this example,
only lines are drawn on the price line - no points.

=item B<*>

In practice the data for the lines would be constructed by another module such as Finance::Shares::Averages.
These support modules add lines in the right way.

=item B<*>

Finally, notice that price_sequence() is used with add_price_line().  Use the right sequence to control the lines.
    
=back

There is no need to be limited to one sequence.  It is possible to have most of the lines controlled by one
sequence but special indicators having their own styles.

B<Example 2>

    my $sample = new Finance::Shares::Sample(
	    price_lines => {
		color	=> 0.5,
		line	=> {},
	    },
	);

    # prepare line data
    $sample->add_price_line($data1, 'One');
    $sample->add_price_line($data2, 'Two');
    
    my $style2 = {
		color	=> [1, 0, 0],
		dashes	=> [],
	    };
	    
    $sample->add_price_line($data3, 'Three', $style2);
    $sample->add_price_line($data4, 'Four');

In this example lines One, Two and Four will be grey, with different dash patterns.  Line Three will be in solid
red.

However, when a PostScript::Graph::Style object is used (rather than a hash ref), it is necessary to explicitly
specify the sequence.

B<Example 3>

    my $sample = new Finance::Shares::Sample(
	    price_lines => {
		color	=> 0.5,
		line	=> {},
	    },
	);

    # prepare line data
    $sample->add_price_line($data1, 'One');
    $sample->add_price_line($data2, 'Two');
    
    my $graph = $sample->graph();
    my $sequence = $graph->price_sequence();
    my $style2 = new PostScript::Graph::Style(
		sequence => $sequence,
		color	 => [1, 0, 0],
		dashes	 => [],
	    );
    $sequence->reset();
	    
    $sample->add_price_line($data3, 'Three', $style2);
    $sample->add_price_line($data4, 'Four');

Passing a style object is the only way of giving the same style to more than one line (boundary lines for
example).  Notice the reset command after $style2 is created.  The other styles are not created until B<output> is
called, so they would otherwise start with the second default.

See L<PostScript::Graph::Style> for details on what is available.

=head1 CONSTRUCTOR

=cut

sub new {
    my $class = shift;
    my $opt = {};
    if (@_ == 1) { $opt = $_[0]; } else { %$opt = @_; }
    
    my $o = {};
    bless( $o, $class );
    $o->{opt} = $opt;
    $o->{plines} = {};
    $o->{vlines} = {};
    $o->{alines} = {};

    ## option defaults
    $o->{tries}  = defined($opt->{tries})    ? $opt->{tries}    : 3;
    $o->{strict} = defined($opt->{strict})   ? $opt->{strict}   : 0;
    $o->{show}   = defined($opt->{show})     ? $opt->{show}     : 1;
   
    $opt->{graph} = {}		unless defined $opt->{graph};
    $opt->{graph}{dates} = {}	unless defined $opt->{graph}{dates};
    my $od = $opt->{graph}{dates};
    $od->{show_year} = 0	unless defined $od->{show_year};
    $o->{dtype} = defined($od->{by}) ? $od->{by} : $opt->{dates_by} || 'data';
   
    # line style options
    $opt->{lines} = {}		unless defined $opt->{lines};

    ## fetch and process data
    carp "'epic' must be specified\n"   unless defined($opt->{epic});
    carp "'source' must be specified\n" unless defined($opt->{source});
    my $type = ref($opt->{source});
    CASE: {
	if ($type eq 'Finance::Shares::MySQL') {
	    $o->{db} = $opt->{source};
	    carp "'start_date' must be specified\n" unless defined($opt->{start_date});
	    carp "'end_date' must be specified\n"   unless defined($opt->{end_date});
	    $o->fetch( $opt->{epic}, $opt->{start_date}, $opt->{end_date}, $opt->{table} );
	    last CASE;
	}
	if ($type eq 'HASH') {
	    $o->{db} = new Finance::Shares::MySQL( $opt->{source} );
	    carp "'start_date' must be specified\n" unless defined($opt->{start_date});
	    carp "'end_date' must be specified\n"   unless defined($opt->{end_date});
	    $o->fetch( $opt->{epic}, $opt->{start_date}, $opt->{end_date}, $opt->{table} );
	    last CASE;
	}
	if ($type eq 'ARRAY') {
	    $o->from_array( $opt->{epic}, $opt->{source} );
	    last CASE;
	}
	if (not $type) {
	    $o->from_csv( $opt->{epic}, $opt->{source}, $opt->{directory} );
	    last CASE;
	}
    }
   
    ## finish
    croak "Finance::Shares::Sample has no data\nStopped" unless ($o->{dates} and @{$o->{dates}});
    
    return $o;
}

=head2 new( [options] )

C<options> can be a hash ref or a list of hash keys and values (or omitted altogether).  

C<source> and C<epic> must be specified, with C<start_date> and C<end_date> also required if the source is
a mysql database.

Recognized keys are:

=head3 source

This can be a Finances::Shares::MySQL object or a hash ref holding options suitable for creating one.
Alternatively it may be the name of a CSV file or an array ref holding similar data.

Example 1

Using an existing MySQL object.

    my $db = new Finance::Shares::MySQL;	    
    my $ss = new Finance::Shares::Sample (
		source => $db,
	    );

Example 2

Creating our own MySQL connection.

    my $ss = new Finance::Shares::Sample (
		source => {
		    user     => 'wally',
		    password => '123jiM',
		    database => 'London',
		},
	    );

Several attempts (see C<tries> below) are made to fetch the data from the internet (see L<Finance::Shares::MySQL/fetch_batch>).  Then the
data is extracted from the MySQL database, filtered according to C<opts> and stored as date, price and volume
data.

!Yahoo Finance provide a suitable source of CSV files in the right format.  If that is what you want you might
like to look at L<Finance::Shares::MySQL> and L<Finance::Shares::Sample>.

The CSV file is read and converted to price and/or volume data, as appropriate.  The comma seperated values are
interpreted by Text::CSV_XS and so are currently unable to tolerate white space.  See the C<array> option for
how the field contents are handled.

Optionally, the directory may be specified seperately.

Example 3

    my $ss = new Finance::Shares::Sample (
		source => 'quotes.csv',
		directory => '~/shares',
	    );

If C<source> is an array ref it should point to a list of arrays with fields date, open, high, low, close and volume.

Example 4

    my $data = [
    ['2002-08-01',645.13,645.13,586.00,606.36,33606236],
    ['2002-08-02',574.75,620.88,558.00,573.00,59618288],
    ['2002-08-05',589.88,589.88,560.11,572.42,20300730],
    ['2002-08-06',571.89,599.00,545.30,585.92,26890880],
    ['2002-08-07',565.11,611.00,560.11,567.11,24977940] ];
    
    my $ss = new Finance::Shares::Sample ( 
		source => $data,
	    );

Three formats are recognized:

    Date, Open, High, Low, Close, Volume
    Date, Open, High, Low, Close
    Date, Volume

Examples

    [2001-04-26, 345, 400, 300, 321, 12345678],
    [Apr-1-01, 234.56, 240.00, 230.00, 239.99],
    [13/4/01, 987654],

The first field must be a date.  Attempts are made to recognize the format in turn:

=over 4

=item 1

The Finance::Shares::MySQL format is tried first, YYYY-MM-DD.

=item 2

European format dates are tried next using Date::Pcalc's Decode_Date_EU().

=item 3

Finally US dates are tried, picking up the !Yahoo format, Mar-01-99.

=back

The four price values are typically decimals and the volume is usually an integer in the millions.  If the option
C<dates> is I<weeks> the average price and volume data for the week is given under the last known day.  Average
prices are also calculated for I<months>.

=head3 dates_by

Control how the data are stored.  Suitable values are 'days', 'weekdays', 'alldays', 'weeks', 'months'.  (Default:
'days')

Shortcut for:
    dates =>{ by => ... }

=head3 directory

Specifies the directory, if C<file> is an unqualified file name.

=head3 end_date

The last day of price data, in YYYY-MM-DD format.  Only used if C<epic> is given.  See L<fetch>.
	    
=head3 epic

The market abbreviation for the stock.  The data is fetched from Yahoo, so there probably should be a suffix
indicating the stock exchange (e.g. BSY.L for BSkyB on the London Stock Exchange).  

If this is given, the stock data is fetched depending on which of C<mysql>, C<file> or C<array> is set.  Remember
to include C<start_date>, C<end_date> and possibly C<table> if C<mysql> is being used.

=head3 graph

If present, the contents is used in a call to L<graph>.  It should be reference to a hash containing options
suitable for a PostScript::Graph::Stock object.  See L<PostScript::Graph::Stock/new>.

The hash referenced here contains a 'dates' key with a sub-hash value used by both this and the
PostScript::Graph::Stock modules.  For details of the keys available within 'dates' see L<prepare_dates>.

=head3 lines

A sub-hash containing style options for price, volume and/or analysis lines.  It is passed straight to
Finance::Shares::Sample.  All PostScript::Graph::Style settings can be used within the three sub-hashes.  See
L<Finance::Shares::Sample> for further details.

Example

    my $ss = new Finance::Shares::Sample ( 
		lines => {
		    price => {
		    },
		    volume => {
		    },
		    analysis => {
		    },
		},
	    );

=head3 show

Setting this to 0 prevents the PostScript::Graph::Stock graph from being created.  (Default: 1)

Individual charts within the PostScript::Graph::Stock object can be hidden by setting their C<percent> option to 0.

=head3 start_date

The first day of price data, in YYYY-MM-DD format.  Only used if C<epic> is given.  See L<fetch>.

=head3 strict

A number of functions can behave strictly according to their definitions or run in a more relaxed way that might
be more benficial.  For example, strictly a 20-day moving average does not exist for the first 20 days.  So with
'strict' set to 1, the function doesn't exist for that period.  But if it is 0, the average so far is returned.
Bollinger bands require 20 days of data from the function they follow.  With 'strict' set, there would have to be
at least 40 days data before the first test could be made.  Without 'strict' a shorter period may be given to the
Bollinger Band function, so this lead time might be reduced to 10 days.  (Default: 0)

=head3 table

The MySQL table name for the stock.  Only used if C<epic> is given.  See L<fetch>.

=head3 tries

Specify the number of times an attempt is made to fetch the data from the internet.  (Default: 3)

=cut

sub add_price_line {
    my ($o, $lineid, $data, $key, $style, $show) = @_;
    croak "No data for price line\nStopped" unless $data;
    croak "No key for price line\nStopped" unless $key;
    my $entry = fields::phash( [@line_fields], [('') x 4] );
    $entry->{data}   = $data;
    $entry->{key}    = $key;
    $entry->{style}  = defined($style) ? $style : $o->{opt}{lines};
    $entry->{show}   = defined($show) ? $show : 1;
    $o->{plines}{$lineid} = $entry;
}

=head2 add_price_line( lineid, data, key [, style [, show]] )

=over 8

=item lineid

A string uniquely identifying the line.

=item data

An array ref indicating a list of points.  Each point has a date and a price value.

=item key

The text to be shown next with the style in the Price Key box to the right of the chart.

=item style

This can either be a PostScript::Graph::Style object or a hash ref holding options for one.

=item show

True if to be drawn, false otherwise.

=back

Add a line to the price chart to be drawn in the style specified identified by some key text.  See
L<PostScript::Graph::Stock/add_price_line>.

=cut

sub add_volume_line {
    my ($o, $lineid, $data, $key, $style, $show) = @_;
    croak "No data for volume line\nStopped" unless $data;
    croak "No key for volume line\nStopped" unless $key;
    my $entry = fields::phash( [@line_fields], [('') x 4] );
    $entry->{data}   = $data;
    $entry->{key}    = $key;
    $entry->{style}  = defined($style) ? $style : $o->{opt}{lines};
    $entry->{show}   = defined($show) ? $show : 1;
    $o->{vlines}{$lineid} = $entry;
}

=head2 add_volume_line( lineid, data, key [, style [, show]] )

See L<add_price_line>.

=cut

sub add_analysis_line {
    my ($o, $lineid, $data, $key, $style, $show) = @_;
    croak "No data for analysis line\nStopped" unless $data;
    croak "No key for analysis line\nStopped" unless $key;
    my $entry = fields::phash( [@line_fields], [('') x 4] );
    $entry->{data}   = $data;
    $entry->{key}    = $key;
    $entry->{style}  = defined($style) ? $style : $o->{opt}{lines};
    $entry->{show}   = defined($show) ? $show : 1;
    $o->{alines}{$lineid} = $entry;
}

=head2 add_analysis_line( data, key [, style [, show [, func, params]]] )

See L<add_price_line>.

=cut

sub build_graph {
    my ($o) = @_;
 
    if ($o->{show}) {
	$o->graph() unless $o->{pgs};
	
	foreach my $line (values %{$o->{plines}}) {
	    $o->{pgs}->add_price_line( $line->{data}, $line->{key}, $line->{style} ) if $line->{show};
	}
	foreach my $line (values %{$o->{vlines}}) {
	    $o->{pgs}->add_volume_line( $line->{data}, $line->{key}, $line->{style} ) if $line->{show};
	}
	foreach my $line (values %{$o->{alines}}) {
	    $o->{pgs}->add_volume_line( $line->{data}, $line->{key}, $line->{style} ) if $line->{show};
	}
    }

    $o->{built} = 1;
    #$o->show_lines();
}

=head2 build_graph()

Construct the graph and add all lines to it.  This should not need to be called in most circumstances as it is
called automatically by B<output>.  However, it is provided so that several samples are to be printed to the same
PostScript::File.  See L<PostScript::Graph::Stock/build_graph>.

Setting the constructor option C<show> to 0 prevents the graph being built.

=cut

sub output {
    my ($o, $file, $dir) = @_;
    $dir = $o->{dir} unless (defined $dir);
   
    if ($o->{show}) {
	$o->build_graph() unless $o->{built};
	$o->{pgs}->output($file, $dir);
    }
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
    
Setting the constructor option C<show> to 0 prevents the graph being built.

=cut

=head1 ACCESS METHODS

See L<DESCRIPTION> for the data items that are directly available.

=cut

sub dates_by {
    return shift()->{dtype};
}

=head2 dates_by

Return a string indicating how the dates are spread.  One of 'data', 'days', 'workdays', 'weeks', 'months'.

=cut

sub line_data {
    my ($o, $chart, @args) = @_;
    my $lines;
    if (@args) {
	if ($chart eq 'price') {
	    $lines = $o->{plines};
	} elsif ($chart eq 'volume') {
	    $lines = $o->{vlines};
	} elsif ($chart eq 'analysis') {
	    $lines = $o->{alines};
	} else {
	    croak "'price', 'volume' or 'analysis' required\nStopped";
	}

	my $key = $o->line_key( @args );
	return $lines->{$key}{data};
    } else {
	if ($chart eq 'price') {
	    return $o->{prices};
	} elsif ($chart eq 'volume') {
	    return $o->{volumes};
	} else {
	    croak "'price', or 'volume' required\nStopped";
	}
    }
}

=head2 line_data( chart [, func, params] )

Return the requested points data.

C<chart> should be one of 'price', 'volume' or 'analysis'.  C<func> and C<params> are as specified when the line
was added.

=cut

sub graph_stock {
    return shift->{pgs};
}

=head2 graph_stock

Return the PostScript::Graph::Stock object used to output the graph.

=cut

=head1 SUPPORT METHODS

=cut

sub fetch {
    my ($o, $epic, $start, $end, $table) = @_;
    $epic = uc($epic);
    ($table = $epic) =~ s/[^\w]/_/g unless $table;
    $o->{epic}  = $epic;
    $o->{table} = $table;
    $o->{start} = $start;
    $o->{end}   = $end;
    
    ## fetch from database
    my $request = [ [ $epic, $start, $end, $table ], ];
    for my $try (1 .. $o->{tries}) {
	my $failed = $o->{db}->fetch_batch( $request );
	last unless ($failed);
    }
    
    $o->{cols} = [qw(Qdate Open High Low Close Volume)];
    $o->{rows} = $o->{db}->select_table($table, $o->{cols}, $start, $end);
    $o->prepare_dates($o->{rows});
}

sub from_csv {
    my ($o, $epic, $file, $dir) = @_;
    my $filename = check_file($file, $dir);
    my @data;
    my $csv = new Text::CSV_XS;
    open(INFILE, "<", $filename) or die "Unable to open \'$filename\': $!\nStopped";
    while (<INFILE>) {
	chomp;
	my $ok = $csv->parse($_);
	if ($ok) {
	    my @row = $csv->fields();
	    push @data, [ @row ] if (@row);
	}
    }
    close INFILE;

    $o->from_array( $epic, \@data );
}

sub from_array {
    my ($o, $epic, $data) = @_;
    die "Array required\nStopped" unless (defined $data);
    $o->{epic} = $epic;
    ($o->{table} = $epic) =~ s/[^\w]/_/g;

    $o->prepare_dates( $data );

    $o->{start} = $o->{dates}[0];
    $o->{end}   = $o->{dates}[$#{$o->{dates}}];
}


sub prepare_dates {
    my $o    = shift;
    my $data = shift;
    my $opt  = $o->{opt}{graph}{dates};

    ## identify date options
    my $dtype = $o->{dtype};
    my ($dsdow, $dsday, $dsmonth, $dsyear, $dsall);
    CASE: {
	if ($dtype eq 'alldays') {
	    ($dsdow, $dsday, $dsmonth, $dsyear) = (1, 1, 1, 0);
	    last CASE;
	}
	if ($dtype eq 'weekdays') {
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
	# ($dtype eq 'data' or 'days')
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
	    ## alldays
	    if ($dtype eq 'alldays') {
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
	    
	    ## weekdays
	    if ($dtype eq 'weekdays') {
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
	    
	    ## weeks
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

	    ## months
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

	    ## days
	    #  ($dtype eq 'data' or 'days')
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

    my (@prices, @volumes, %index);
    for (my $i = 0; $i <= $#dates; $i++) {
	my $date = $dates[$i];
	$index{$date} = $i;
	push @prices, $price{$date}[3];
	push @volumes, $volume{$date};
    }
  
    ## data defined
    $o->{order}   = \%order;	    # maps YYYY-MM-DD date to {labels} index
    $o->{price}   = \%price;	    # maps YYYY-MM-DD date to array of [open, high, low, close]
    $o->{volume}  = \%volume;	    # maps YYYY-MM-DD date to volume
    $o->{idx}     = \%index;	    # maps YYYY-MM-DD date to {dates} index
    $o->{dates}   = \@dates;	    # array of known dates
    $o->{prices}  = \@prices;	    # closing prices in {dates} order
    $o->{volumes} = \@volumes;	    # volumes in {dates} order
    $o->{labels}  = \@labels;	    # all labels, needed by PostScript::Graph::Stock
    $o->{lblmax}  = $labelmax;	    # size of longest label, needed by PostScript::Graph::Stock
}

=head2 prepare_dates( data )

This splits raw CSV-style data into the date labels, prices and volumes needed for a stock graph.
C<data> should be a reference to an array of arrays.  The inner arrays should hold a date in YYYY-MM-DD format,
opening, high, low and closing prices followed by the volume.  Either the prices or the volume may be omitted. 

Example

    $data = [
    ['2001-06-01',454.50,475.00,448.50,461.00,8535680],
    ['2001-06-04',465.00,465.00,458.50,459.00,3254045],
    ['2001-06-05',458.25,464.00,455.00,462.00,4615016],
    ];

The dates are filtered and labelled according to the 'dates' sub-hash options passed to the constructor.  Suitable
values for keys found within 'dates' are processed by this method and so are listed here.

=head3 by

This string determines how the dates are distributed across the X axis.

=over 4

=item B<days>

The dates are those present in the data, in chronological order (the default).

=item B<alldays>

Every day between the first and last day is listed, whether there is data for that day or not.

=item B<weekdays>

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

sub known_date {
    my ($o, $req) = @_;
    foreach my $date (@{$o->{dates}}) {
	return $date if ($date ge $req);
    }
    return undef;
}

=head2 known_date( date )

Adjust the YYYY-MM-DD date given to one of the dates with data.  It actually returns the date given or the first
one after it rather than the closest.  Returns undef if no date is found.

=cut

sub graph {
    my $o = shift;
    if ($o->{show}) {
	my $opt = $o->{opt}{graph};
	my $epic = $o->{epic};
	die "No data.  A 'sample', 'file' or 'array' must be given to Finance::Shares::Sample->new.\nStopped" 
	    unless (defined $epic);
	my @date = $o->{end} ? ymd_from_string($o->{end}) : Today();
	my $end_date = Date_to_Text_Long( @date );
	my $dtype = ucfirst($o->{dtype});
	$opt->{sample} = $o;
	$opt->{heading} = "$epic Shares, $dtype to $end_date";
	$opt->{file}    = {} unless (defined $opt->{file});
	my $of = $opt->{file};
	unless (ref($of) eq 'PostScript::File') {
	    $of->{landscape} = 1 unless (defined $of->{landscape});
	    $of->{errors}    = 1 unless (defined $of->{errors});
	}
	
	$o->{pgs} = new PostScript::Graph::Stock( $opt );
    }
    return $o->{pgs};
}

=head2 graph

All options should be given as the constructor option, C<graph>.  This should only need to be called if the
underlying PostScript::Graph::Stock object (which is returned) is needed.

=cut


sub eval_data {
    my ($o, $chart, $date, $id) = @_;
    if ($chart eq 'price') {
	my $i = $pricepos{$id};
	$i = 3 unless defined $i;
	return $o->{price}{$date}[$i];
    } elsif ($chart eq 'volume') {
	my $i = $o->{idx}{$date};
	return $o->{volumes}[$i] if defined $i;
    }
    return undef;
}
# if $chart is 'price', $id may be 'open', 'high', 'low' or 'close'

sub eval_line {
    my ($o, $chart, $date, $id) = @_;
    croak "No date to evaluate\nStopped" unless defined $date;
    croak "No function to evaluate\nStopped" unless $id;
    my $hash;
    if ($chart eq 'price') {
	$hash = $o->{plines};
    } elsif ($chart eq 'volume') {
	$hash = $o->{vlines};
    } elsif ($chart eq 'analysis') {
	$hash = $o->{alines};
    } else {
	croak "Chart not given\nStopped";
    }
    return undef unless defined $hash;
    
    my $line = $hash->{$id};
    if (defined $line) {
	my $i = $o->{idx}{$date};
	return $line->{data}[$i][1] if defined $i;    
    }
    return undef;
}

sub line_key {
    no warnings;
    my $key = join('_', @_);
    use warnings;
    return $key;
}
# generate key for plines, vlines or alines

### Formats
our ($slt_chart, $slt_id, $slt_key, $slt_show);
format Show_Lines_Top =
Chart    Line Id                        Chart Key                          Show
======== ============================== ================================== ====
.

format Show_Lines =
@<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>>
$slt_chart, $slt_id,                    $slt_key,                          $slt_show
.

sub show_lines {
    my $o = shift;

    my $fh = select STDOUT;
    $~ = 'Show_Lines';
    $^ = 'Show_Lines_Top';
    foreach my $key (keys %{$o->{plines}}) {
	my $line = $o->{plines}{$key};
	if (defined $line) {
	    $slt_chart = 'price';
	    $slt_id    = $key;
	    $slt_key   = $line->{key}  || '';
	    $slt_show  = $line->{show} || '';
	    write STDOUT;
	}
    }
    foreach my $key (keys %{$o->{vlines}}) {
	my $line = $o->{plines}{$key};
	if (defined $line) {
	    $slt_chart = 'volume';
	    $slt_id    = $key;
	    $slt_key   = $line->{key}  || '';
	    $slt_show  = $line->{show} || '';
	    write STDOUT;
	}
    }
    foreach my $key (keys %{$o->{vlines}}) {
	my $line = $o->{plines}{$key};
	if (defined $line) {
	    $slt_chart = 'analysis';
	    $slt_id    = $key;
	    $slt_key   = $line->{key}  || '';
	    $slt_show  = $line->{show} || '';
	    write STDOUT;
	}
    }
    $~ = 'STDOUT';
    $^ = 'STDOUT_TOP';
}

=head1 BUGS

Please report those you find to the author.

=head1 AUTHOR

Chris Willmot, chris@willmot.co.uk

=head1 SEE ALSO

L<Finance::Shares::MySQL>,
L<Finance::Shares::Model>,
L<PostScript::Graph::Style> and
L<PostScript::Graph::Stock>.

=cut

1;
