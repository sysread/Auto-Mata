#-------------------------------------------------------------------------------
# Calculates fibonacci numbers for arguments passed into the command line
#
# The algorithm used is based on the solution described here:
#   http://stackoverflow.com/a/16389221
#-------------------------------------------------------------------------------
use strict;
use warnings;
use Scalar::Util 'looks_like_number';
use Types::Standard -all;
use Type::Utils -all;
use Auto::Mata;

# Scalar terms
my $AboveZero = declare 'AboveZero', as Str, where { looks_like_number($_) && $_ >= 0 };
my $Zero = declare 'Zero', as $AboveZero, where { $_ == 0 };
my $One  = declare 'One',  as $AboveZero, where { $_ == 1 };
my $Term = declare 'Term', as $AboveZero, where { $_ >= 2 };

# Accumulator constructs
my $Start   = declare 'Start',   as Tuple[$AboveZero];
my $Step    = declare 'Step',    as Tuple[$Term, $AboveZero, $AboveZero];
my $CarZero = declare 'CarZero', as Tuple[$Zero, $AboveZero, $AboveZero];
my $CarOne  = declare 'CarOne',  as Tuple[$One,  $AboveZero, $AboveZero];

my $Fibs = machine {
  ready 'READY';
  term  'TERM';

  # Fail on invalid input
  transition 'READY', to 'TERM', on ~$AboveZero, with { die 'invalid argument; expected an integer >= 0' };

  # Build the initial accumulator
  transition 'READY', to 'STEP', on $AboveZero, with { [$_, 1, 0] };

  # Step through the series until a result is found when the step hits 1 or 0
  transition 'STEP', to 'REDUCE', on $Step, with { [$_->[0] - 1, $_->[1] + $_->[2], $_->[1]] };
  transition 'REDUCE', to 'STEP', with { $_ };

  transition 'STEP', to 'ZERO', on $CarZero, with { $_ };
  transition 'ZERO', to 'TERM', with { $_->[2] };

  transition 'STEP', to 'ONE', on $CarOne, with { $_ };
  transition 'ONE',  to 'TERM', with { $_->[1] };

  # Return the final result
  transition 'STEP', to 'TERM', on $AboveZero;
};

sub fib {
  my $term = shift;
  my $calc = $Fibs->();
  my $acc  = $term;

  while (my @state = $calc->($acc)) {
    ;
  }

  return $acc;
}

local $| = 1;

foreach my $term (@ARGV) {
  print "fib($term) = ";
  print fib($term), "\n";
}
