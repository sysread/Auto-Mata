use strict;
use warnings;
use List::Util qw(reduce);
use Types::Standard -all;
use Type::Utils -all;
use Auto::Mata;

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

my $Term       = declare 'Term',       as Num;
my $Op         = declare 'Op',         as Enum[keys %OP];
my $Exit       = declare 'Exit',       as Enum[qw(quit q exit x)];
my $Input      = declare 'Input',      as $Term | $Op | $Exit;
my $Stack      = declare 'Stack',      as ArrayRef[$Input];
my $Incomplete = declare 'Incomplete', as ArrayRef[$Term];
my $Equation   = declare 'Equation',   as Tuple[$Op, $Term, $Term, slurpy ArrayRef[$Term]];
my $ExitCmd    = declare 'ExitCmd',    as Tuple[$Exit, slurpy ArrayRef[$Term]];
my $Invalid    = declare 'Invalid',    as Tuple[~$Input, slurpy ArrayRef[Any]];

my $builder = machine {
  ready 'READY';
  terminal 'TERM';

  transition 'READY', to 'INPUT',
    on $Incomplete,
    with { welcome; [] };

  transition 'INPUT', to 'INPUT',
    on $Incomplete,
    with { unshift @$_, input; $_ };

  transition 'INPUT', to 'ANSWER',
    on $Equation,
    with { solve; [] };

  transition 'INPUT', to 'ERROR',
    on $Invalid,
    with { error; $_ };

  transition 'ERROR', to 'INPUT',
    on $Invalid,
    with { shift @$_; $_ };

  transition 'INPUT', to 'TERM',
    on $ExitCmd,
    with { goodbye; [] };

  transition 'ANSWER', to 'INPUT',
    on $Incomplete;
};

my $stack = [];
my $fsm = $builder->($stack);

my $backstop = 50;
while ($fsm->()) {
  die "backstop reached" if --$backstop == 0;
  ;
}
