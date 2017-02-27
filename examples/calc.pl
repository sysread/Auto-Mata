use strict;
use warnings;
use List::Util qw(reduce);
use Data::State;
use Types::Standard -all;

my %OP = (
  '+'  => sub { $_[0]  + $_[1] },
  '-'  => sub { $_[0]  - $_[1] },
  '*'  => sub { $_[0]  * $_[1] },
  '/'  => sub { $_[0]  / $_[1] },
  '**' => sub { $_[0] ** $_[1] },
);

sub welcome { print "\nWelcome to the example calculator!\n\n" }
sub goodbye { print "\nThanks for playing! Goodbye!\n\n" }

sub error {
  my $invalid = $_->[0];
  if (exists $OP{$invalid}) {
    print "At least two terms are required before an operator may be applied.\n\n";
  } else {
    print "I do not understand '$invalid'. Please enter a term or operator.\n\n";
  }
}

sub input {
  my @terms = reverse @$_;
  print "terms> @terms\n" if @terms;
  print "input> ";

  my $value = <STDIN>;
  print "\n";

  ($value) = $value =~ /\s*(.*)\s*$/;
  reverse split /\s+/, $value;
}

sub solve {
  my ($op, @terms) = @$_;
  @terms = reverse @terms;
  my $n  = reduce { $OP{$op}->($a, $b) } @terms;
  my $eq = join " $op ", @terms;
  print "  $eq = $n\n\n";
}

my $Term       = Num;
my $Op         = Enum[keys %OP];
my $Exit       = Enum[qw(quit q exit x)];
my $Input      = $Exit | $Op | $Term;

my $Stack      = ArrayRef[$Input];
my $Incomplete = ArrayRef[$Term];
my $Equation   = Tuple[$Op, $Term, $Term, slurpy ArrayRef[$Term]];
my $ExitCmd    = Tuple[$Exit, slurpy ArrayRef[$Input]];

my $Valid      = $Incomplete | $Equation | $ExitCmd;
my $Invalid    = $Valid->complementary_type;

my $builder = machine {
  ready 'READY';
  terminal 'TERM';

  transition 'READY', to 'INPUT',
    on $Incomplete,
    with { welcome };

  transition 'INPUT', to 'INPUT',
    on $Incomplete,
    with { unshift @$_, input };

  transition 'INPUT', to 'ANSWER',
    on $Equation,
    with { solve; @$_ = () };

  transition 'INPUT', to 'ERROR',
    on $Invalid,
    with { error };

  transition 'ERROR', to 'INPUT',
    on $Invalid,
    with { shift @$_ };

  transition 'INPUT', to 'TERM',
    on $ExitCmd,
    with { goodbye };

  transition 'ANSWER', to 'INPUT',
    on $Incomplete;
};

my @stack;
my $fsm = $builder->(\@stack);

while (my $state = $fsm->()) {
  ;
}
