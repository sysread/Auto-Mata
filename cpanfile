requires 'Carp'            => 0;
requires 'Data::Dumper'    => 0;
requires 'Exporter'        => 0;
requires 'List::Util'      => 0;
requires 'Type::Params'    => 0;
requires 'Type::Tiny'      => 0;
requires 'Type::Utils'     => 0;
requires 'Types::Standard' => 0;

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
};
