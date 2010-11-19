use inc::Module::Install;

all_from 'lib/CSE598/Project2.pm';

auto_include_deps;
install_script 'script/project2.pl';
install_script 'script/create_node_map.pl';
install_script 'script/anonymize.pl';
WriteAll;
