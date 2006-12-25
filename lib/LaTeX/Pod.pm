package LaTeX::Pod;

use strict;
use warnings;

use Carp qw(croak);
use LaTeX::TOM;

our $VERSION = '0.01';

sub new {
    my ($self, $file) = @_;
    my $class = ref($self) || $self;
    croak "No path to latex file provided!" unless $file;
    return bless { file => $file }, $class;
}

sub convert {
    my $self = shift;

    my $nodes = $self->init_tom();

    foreach my $node (@$nodes) {
        $self->{current_node} = $node;
        my $type = $node->getNodeType();
        if ($type =~ /TEXT|COMMENT/) {
            next unless $node->getNodeText() =~ /\w+/;
            if ($self->_is_set_node('title')) {
                $self->_process_text_title();
            } elsif ($self->_is_set_node('verbatim')) {
                $self->_process_text_verbatim();
            } elsif ($node->getNodeText() =~ /\\item\[.*?\]/) {
                $self->_process_text_item();
            } 
        } elsif ($type =~ /ENVIRONMENT/) {
            $self->_process_verbatim();
        } elsif ($type =~ /COMMAND/) {
            $self->_unregister_previous('verbatim');
            if ($self->_is_set_previous('item')) {
                $self->_process_item();
            }
            if ($node->getCommandName() eq 'section') {
                $self->_process_section();
            } elsif ($node->getCommandName() =~ /subsection/) {
                $self->_process_subsection();
            }
            my $cmd_name = $node->getCommandName();
            if ($cmd_name eq 'textbf') {
                $self->_process_text_subst_tags($cmd_name);
            } elsif ($cmd_name eq 'emph') {
                $self->_process_text_subst_tags($cmd_name);
            } elsif ($cmd_name eq 'textsf') {
                $self->_process_text_subst_tags($cmd_name);
            }
        }
    }

    return $self->{pod};
}

sub _init_tom {
    my $self = shift;

    my $parser = Parser->new();
    my $document = $parser->parseFile($self->{file});
    my $nodes = $document->getAllNodes();

    return $nodes;
}

sub _process_text_title {
    my $self = shift;

    if ($self->is_set_previous('item')) { 
        $self->{pod} .= "=back\n\n";
    }

    $self->{pod} .= $self->{current_node}->getNodeText(). "\n";

    $self->unregister_node('title');
    $self->register_previous('title');
}

sub _process_text_verbatim {
    my $self = shift;

    my $text = $self->{current_node}->getNodeText();

    unless ($self->is_set_previous('verbatim') 
         || $self->is_set_previous('item')) {
        $text .= "\n";
    }

    if (!$self->is_set_previous('item')) {
        $text =~ s/^(.*)$/\ $1/gm;
    } else {
        $text =~ s/(.*)/\n$1/;
    }

    $self->{pod} .= $text;

    $self->unregister_node('verbatim');
    $self->unregister_previous('title');
    $self->register_previous('verbatim');
}

sub _process_text_item {
    my $self = shift;

    unless ($self->is_set_previous('item')) { 
        $self->{pod} .= "\n=over 4\n";
    }

    my $text = $self->{current_node}->getNodeText();

    $text =~ s/\\item\[(.*?)\]/\=item $1/g;
    $text =~ s/^\n//;
    $text =~ s/\n$//;

    $self->{pod} .= $text;

    $self->register_previous('item');
}

sub _process_text_subst_tags {
    my ($self, $tag) = @_;

    my $node = $self->{current_node}->getFirstChild();
    my $text = $node->getNodeText();

    if ($tag eq 'textbf') {
        $self->{pod} .= "B<$text>";
    } elsif ($tag eq 'emph') {
        $self->{pod} .= "I<$text>";
    } elsif ($tag eq 'textsf') {
        $self->{pod} .= "C<$text>";
    }

    $self->{pod} .= "\n";
}

sub _process_verbatim {
    my $self = shift;

    $self->unregister_previous('verbatim');

    if ($self->{current_node}->getEnvironmentClass() eq 'verbatim') {
        $self->register_node('verbatim');
    }
}

sub _process_item {
    my $self = shift;

    unless ($self->{current_node}->getCommandName() eq 'mbox') {
        if ($self->is_set_previous('item')) {
            $self->{pod} .= "\n=back\n";
        }

        $self->{pod} .= "\n";

        $self->unregister_previous('item');
    }
}

sub _process_section {
    my $self = shift;

    if ($self->is_set_previous('title') || $self->is_set_previous('item')) {
        $self->{pod} .= "\n\n";
        $self->unregister_previous('title');
        $self->unregister_previous('item');
    }

    $self->{pod} .= '=head1 ';

    $self->register_node('title');
}

sub _process_subsection {
    my $self = shift;

    my $sub_often;
    my $var = $self->{current_node}->getCommandName();

    while ($var =~ s/sub(.*)/$1/g) {
        $sub_often++;
    }

    if ($self->is_set_previous('title')) {
        $self->{pod} .= "\n";
        $self->unregister_previous('title');
    }

    $self->{pod} .= '=head'.($sub_often+1).' ';

    $self->register_node('title');
}

sub _register_node {
    my ($self, $item) = @_;
    $self->{node}{$item} = 1;
}

sub _is_set_node {
    my ($self, $item) = @_;
    return $self->{node}{$item} ? 1 : 0;
}

sub _unregister_node {
    my ($self, $item) = @_;
    delete $self->{node}{$item};
}

sub _register_previous {
    my ($self, $item) = @_;
    $self->{previous}{$item} = 1;
}

sub _is_set_previous {
    my ($self, $item) = @_;
    return $self->{previous}{$item} ? 1 : 0;
}

sub _unregister_previous {
    my ($self, $item) = @_;
    delete $self->{previous}{$item};
}

=head1 NAME

LaTeX::Pod - Transform LaTeX source files to POD (Plain old documentation)

=head1 SYNOPSIS

 use LaTeX::Pod;

 my $parser = LaTeX::Pod->new('/path/to/latex/source');
 print $parser->convert();

=head1 DESCRIPTION

C<LaTeX::Pod> converts LaTeX sources to Perl's POD (Plain old documentation)
format. Currently only a subset of the available LaTeX language is suppported -
see below for detailed information.

=head1 CONSTRUCTOR

=head2 new

The constructor requires that the path to the latex source must be declared:

 $parser = LaTeX::Pod->new('/path/to/latex/source');

Returns the parser object.

=head1 METHODS

=head2 convert

There is only one public method available, C<convert()>:

 $parser->convert();

Returns the POD document as string.

=head1 SUPPORTED LANGUAGE SUBSET

It's not much, but there's more to come:

=over 4

=item sections/subsections

=item verbatim blocks

=item itemized lists

=item plain text

=item bold/italic/code font tags

=back

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
