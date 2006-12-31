package LaTeX::Pod;

use strict;
use warnings;

use Carp qw(croak);
use LaTeX::TOM;

our $VERSION = '0.05';

sub new {
    my ($self, $file) = @_;
    my $class = ref($self) || $self;
    croak "No valid path to latex file provided: $!" unless -f $file;
    return bless { file => $file }, $class;
}

sub convert {
    my $self = shift;

    my $nodes = $self->_init_tom();

    $self->{title_inc} = 1;

    foreach my $node (@$nodes) {
        $self->{current_node} = $node;
        my $type = $node->getNodeType();
        if ($type =~ /TEXT|COMMENT/) {
            next if $node->getNodeText() !~ /\w+/
                 or $node->getNodeText() =~ /^\\\w+$/m
                 or $self->_process_directives();
            if ($self->_is_set_node('title')) {
                $self->_process_text_title();
            } elsif ($self->_is_set_node('verbatim')) {
                $self->_process_text_verbatim();
            } elsif ($node->getNodeText() =~ /\\item/) {
                $self->_process_text_item();
            } elsif ($self->_is_set_node('textbf')) {
                $self->_process_tags('textbf');
            } elsif ($self->_is_set_node('textsf')) {
                $self->_process_tags('textsf');
            } elsif ($self->_is_set_node('emph')) {
                $self->_process_tags('emph');
            } else {
                $self->_process_text();
           }
        } elsif ($type =~ /ENVIRONMENT/) {
            $self->_process_verbatim();
        } elsif ($type =~ /COMMAND/) {
            $self->_unregister_previous('verbatim');
            my $cmd_name = $node->getCommandName();
            if ($self->_is_set_previous('item')) {
                $self->_process_item();
            } elsif ($cmd_name eq 'chapter') {
                $self->_process_chapter();
            } elsif ($cmd_name eq 'section') {
                $self->_process_section();
            } elsif ($cmd_name =~ /subsection/) {
                $self->_process_subsection();
            } elsif ($cmd_name =~ /documentclass|usepackage|pagestyle/) {
                $self->_register_node('directive');
            } elsif ($cmd_name eq 'title') {
                $self->_register_node('doctitle');
            } elsif ($cmd_name eq 'author') {
               $self->_register_node('docauthor');
            } elsif ($cmd_name =~ /textbf|textsf|emph/) {
               $self->_register_node($cmd_name);
            }
        }
    }

    my $pod = $self->_pod_get();
    $pod =~ s/\n{2,}/\n\n/g;
    $self->_pod_set($pod);

    return $pod;
}

sub _init_tom {
    my $self = shift;

    # silently discard warnings about unparseable latex
    my $parser = Parser->new(2);
    my $document = $parser->parseFile($self->{file});
    my $nodes = $document->getAllNodes();

    return $nodes;
}

sub _process_directives {
    my $self = shift;

    if ($self->_is_set_node('directive')) {
        $self->_unregister_node('directive');
        return 1;
    } elsif ($self->_is_set_node('doctitle')) {
        $self->_unregister_node('doctitle');
        $self->_pod_add("=head1 " . $self->{current_node}->getNodeText());
        return 1;
    } elsif ($self->_is_set_node('docauthor')) {
        $self->_unregister_node('docauthor');
        $self->_pod_add(' (' . $self->{current_node}->getNodeText() . ')');
        return 1;
    }

    return 0;
}

sub _process_text_title {
    my $self = shift;

    if ($self->_is_set_previous('item')) { 
        $self->_pod_add("=back\n\n");
    }

    my $text = $self->{current_node}->getNodeText();

    $self->_process_spec_chars(\$text);

    $self->_pod_add($text . "\n");

    $self->_unregister_node('title');
    $self->_register_previous('title');
}

sub _process_text_verbatim {
    my $self = shift;

    my $text = $self->{current_node}->getNodeText();

    unless ($self->_is_set_previous('verbatim')) {
        $text =~ s/^\n//s;
        $text =~ s/\n$//s if $text =~ /\n{2,}$/;
    }

    unless ($self->_is_set_previous('verbatim') 
         || $self->_is_set_previous('item')
         || $self->_is_set_previous('text')) {
        $text .= "\n";
    }

    if ($self->_is_set_previous('item') ||
        $self->_is_set_previous('text')) {
        $text =~ s/^(.*)$/\ $1/gm;
    } else {
        $text =~ s/(.*)/\n$1/;
    }

    $self->_pod_add($text);

    $self->_unregister_node('verbatim');
    $self->_unregister_previous('title');
    $self->_register_previous('verbatim');
}

sub _process_text_item {
    my $self = shift;

    unless ($self->_is_set_previous('item')) { 
        $self->_pod_add("\n=over 4\n");
    }

    my $text = $self->{current_node}->getNodeText();

    $text =~ s/\\item\[?(.*?)\]?/\=item $1/g;
    $text =~ s/^\n//;
    $text =~ s/\n$//;

    $self->_process_spec_chars(\$text);

    $self->_pod_add($text);

    $self->_register_previous('item');
}

sub _process_text {
    my $self = shift;

    my $text = $self->{current_node}->getNodeText();

    $self->_process_spec_chars(\$text);

    $self->_pod_add($text);

    $self->_register_previous('text');
}

sub _process_verbatim {
    my $self = shift;

    $self->_unregister_previous('verbatim');

    if ($self->{current_node}->getEnvironmentClass() eq 'verbatim') {
        $self->_register_node('verbatim');
    }
}

sub _process_item {
    my $self = shift;

    unless ($self->{current_node}->getCommandName() eq 'mbox') {
        if ($self->_is_set_previous('item')) {
            $self->_pod_add("\n=back\n");
        }

        $self->_pod_add("\n");

        $self->_unregister_previous('item');
    }
}

sub _process_chapter {
    my $self = shift;

    if ($self->_is_set_previous('title')) {
        $self->_unregister_previous('title');
    }

    $self->{title_inc}++;

    $self->_pod_add('=head1 ');

    $self->_register_node('title');
}

sub _process_section {
    my $self = shift;

    if ($self->_is_set_previous('title') 
     || $self->_is_set_previous('item') 
     || $self->_is_set_previous('text')) {
        $self->_pod_add("\n\n");
        $self->_unregister_previous('title');
        $self->_unregister_previous('item');
        $self->_unregister_previous('text');
    }

    $self->_pod_add('=head'.$self->{title_inc}.' ');

    $self->_register_node('title');
}

sub _process_subsection {
    my $self = shift;

    my $sub_often;
    my $var = $self->{current_node}->getCommandName();

    while ($var =~ s/sub(.*)/$1/g) {
        $sub_often++;
    }

    if ($self->_is_set_previous('title')
     || $self->_is_set_previous('text')
     || $self->_is_set_previous('verbatim')) {
        $self->_pod_add("\n");
        $self->_unregister_previous('title');
        $self->_unregister_previous('text');
        $self->_unregister_previous('verbatim');
    }

    $self->_pod_add('=head'.($self->{title_inc}+$sub_often).' ');

    $self->_register_node('title');
}

sub _process_spec_chars {
    my ($self, $text) = @_;

    $$text =~ s/\\\"A/Ä/g;
    $$text =~ s/\\\"a/ä/g;
    $$text =~ s/\\\"U/Ü/g;
    $$text =~ s/\\\"u/ü/g;
    $$text =~ s/\\\"O/Ö/g;
    $$text =~ s/\\\"o/ö/g;

    $$text =~ s/\\_/\_/g;
    $$text =~ s/\\\$/\$/g;

    $$text =~ s/\\verb(.)(.*?)\1/C<$2>/g;
    $$text =~ s/\\newline/\n/g;
}

sub _process_tags {
    my ($self, $tag) = @_;

    my $text = $self->{current_node}->getNodeText();

    my %tags = (textbf => 'B',
                textsf => 'C',
                emph   => 'I');

    $self->_pod_add("$tags{$tag}<$text>");

    $self->_unregister_node($tag);
}

sub _pod_add {
    my ($self, $content) = @_;
    $self->{pod} .= $content;
}

sub _pod_get {
    my $self = shift;
    return $self->{pod};
}

sub _pod_set {
    my ($self, $pod) = @_;
    $self->{pod} = $pod;
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

=item * chapters

=item * sections/subsections

=item * verbatim blocks

=item * itemized lists

=item * plain text

=item * bold/italic/code font tags

=item * umlauts

=back

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
