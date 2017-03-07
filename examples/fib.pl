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

my $Number   = declare 'Number', as Str, where { looks_like_number $_ };
my $ZeroPlus = declare 'ZeroPlus', as $Number, where { $_ >= 0 };
my $Zero     = declare 'Zero', as $Number, where { $_ == 0 };
my $One      = declare 'One',  as $Number, where { $_ == 1 };
my $Term     = declare 'Term', as $Number, where { $_ >= 2 };
my $Start    = declare 'Start', as Tuple[$ZeroPlus];
my $Step     = declare 'Step', as Tuple[$Term, $ZeroPlus, $ZeroPlus];
my $CarZero  = declare 'CarZero', as Tuple[$Zero, $ZeroPlus, $ZeroPlus];
my $CarOne   = declare 'CarOne', as Tuple[$One,  $ZeroPlus, $ZeroPlus];

my $Fibs = machine {
  ready 'READY';
  term  'TERM';

  # Fail on invalid input
  transition 'READY', to 'TERM', on ~$ZeroPlus, with { die 'invalid argument; expected an integer >= 0' };

  # Build the initial accumulator
  transition 'READY', to 'STEP', on $ZeroPlus, with { [$_, 1, 0] };

  # Step through the series until a result is found when the step hits 1 or 0
  transition 'STEP', to 'REDUCE', on $Step, with { [$_->[0] - 1, $_->[1] + $_->[2], $_->[1]] };
  transition 'REDUCE', to 'STEP';

  transition 'STEP', to 'ZERO', on $CarZero;
  transition 'ZERO', to 'TERM', with { $_->[2] };

  transition 'STEP', to 'ONE', on $CarOne;
  transition 'ONE', to 'TERM', with { $_->[1] };

  # Return the final result
  transition 'STEP', to 'TERM', on $ZeroPlus;
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
