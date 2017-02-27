use strict;
use warnings;
use Auto::Mata;
use Types::Standard -types;

my $NoData   = Dict[first => Optional[Str], last => Optional[Str], age => Optional[Int]];
my $HasFirst = Dict[first => Str, last => Optional[Str], age => Optional[Int]];
my $HasLast  = Dict[first => Str, last => Str, age => Optional[Int]];
my $Complete = Dict[first => Str, last => Str, age => Int];

sub get_input {
  my $query = shift;
  print "\n$query ";
  my $input = <STDIN>;
  chomp $input;
  return $input;
}

my $fsm = machine {
  ready 'READY';
  terminal 'TERM';

  transition 'READY', to 'FIRST',
    on $NoData,
    with { $_->{first} = get_input("What is your first name? ") };

  transition 'FIRST', to 'LAST',
    on $HasFirst,
    with { $_->{last} = get_input("What is your last name? ") };

  transition 'LAST', to 'AGE',
    on $HasLast,
    with { $_->{age} = get_input("What is your age? ") };

  transition 'AGE', to 'TERM',
    on $Complete;
};

my $data = {};
my $prog = $fsm->($data);

while ($prog->()) {
  ;
}

print "Hello $data->{first} $data->{last}, aged $data->{age} years.\n";
