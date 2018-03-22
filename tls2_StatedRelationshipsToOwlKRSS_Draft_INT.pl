#!/usr/local/bin/perl -w
#
#   Copyright (c) 2012 International Health Terminology Standards Development Organisation
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OR ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License
#
#   Version 4.1, Date: 2012-07-31, Author: Kent Spackman
#   OWL API VERSION COMPATIBILITY NOTE: The version of OWL Functional Syntax is that required by OWL API 3.2
#
# Run the script as "perl <scriptfilename> <arg0> <arg1> <arg2> <arg3> <arg4>" where
#  <scriptfilename> is the name of the file containing this script
#  <arg0> can be KRSS, OWL, or OWLF:
#			KRSS: This produces KRSS2 which is parsable by the OWL API 3.2, or by CEL or other classifiers
#			OWL:  This produces the OWL XML/RDF format.
#			OWLF: This produces the OWL functional syntax, parsable by the OWL API 3.2
#  <arg1> is the name of the file containing the SNOMED CT RF2 Concepts Table snapshot e.g. sct2_Concept_Snapshot_INT_20120731.txt
#  <arg2> is the name of the file containing the SNOMED CT RF2 Descriptions Table snapshot e.g. sct2_Description_Snapshot_INT_20120731.txt
#  <arg3> is the name of the file containing the SNOMED CT RF2 Stated Relationships Table snapshot, e.g. sct2_StatedRelationship_Snapshot_INT_20120731.txt
#  <arg4> is the name of the file containing the SNOMED CT RF2 Concrete Domain reference set snapshot, e.g. der2_ccsRefset_ConcreteDomains_INT_20120731.txt
#  <arg5> is the name of the output file, which is your choice but could be something like res_StatedRDFXML_Core_INT_20120731.owl
#
# It outputs a description logic representation, using either OWL or KRSS syntax.
# KRSS Notes:
#    The KRSS uses "define-primitive-concept" instead of the contracted "defprimconcept", and
#    "define-concept" instead of the contracted "defconcept", and "define-primitive-role" instead
#    of the contracted "defprimrole".
# OWL Notes:
#    The OWL syntax can be either RDF/XML or OWL Functional Syntax.  The OWL sublanguage used (OWL 2 profile) is OWL 2 EL.
# The output files can be imported into an editor such as Protege using the OWL API.
# Tested with OWL API version 3.2.3 in Protege 4.1, and with OWL API version 3.2.5 in Protege 4.2 beta. 

# The script relies on the hierarchy under 410662002 "Concept model attribute" to specify the role hierarchies.

# The output consists of:
# 1) A set of role definitions
# 2) A set of concept definitions.

###############################################################################
# Current limitations of this script and TODO list
#  - Only 1 input concrete domain refset file is processable (requires that 
#    users concatenate multiple files into one before using this script)
#  - IDs for metadata (measurement type refsets and equals operator) are from
#    AMT v3 and the NEHTA namespace as no equivalent exists in SNOMED CT yet
#  - Only supports for the equality operator
#  - Only supports float and integer (only ones specified in the spec so far)
#  - Only supports OWL Functional Syntax
#  - Missing an identifier (from SNOMED CT and AMT v3) for the "unit" role from
#    the concrete domain reference sets
#
# These limitations are to be addressed over time, however currently the script
# is sufficient to transform AMT v3 which can be downloaded from - 
# https://nehta.org.au/aht/index.php?option=com_docman&task=doc_download&gid=534&Itemid=40
###############################################################################

use English;

my %fsn;
my %primitive;
my %parents;
my %children;
my %rels;
my %roles;
my %rightids;
my %nevergrouped;

# -------------------------------------------------------------------------------------------
# SPECIAL DECLARATIONS for attribute hierarchy, IS A relationships, non-grouping, and right identities
# CAUTION: The values for these parameters depend on the particular release of SNOMED CT.
# Do not assume they remain stable across different releases. These values are valid for 20120131, release format 2 (RF2).
# -------------------------------------------------------------------------------------------

$conceptModelAttID = "410662002"
  ; # the SCTID of the concept at the top of the concept model attribute hierarchy
$isaID = "116680003";    # the SCTID of the IS A relationship concept
$nevergrouped{"123005000"} = "T";    # part-of is never grouped
$nevergrouped{"272741003"} = "T";    # laterality is never grouped
$nevergrouped{"127489000"} = "T";    # has-active-ingredient is never grouped
$nevergrouped{"411116001"} = "T";    # has-dose-form is never grouped
$rightid{"363701004"}      =  "127489000";    # direct-substance o has-active-ingredient -> direct-substance

$conceptDefinedId = "900000000000073002";
$FSNId = "900000000000003001";

# The following 3 constants are from AMT v3 because there are no equivalents from SNOMED CT yet.
$measurementTypeFloat = "700001351000036100";
$measurementTypeInt = "700001361000036102";
$equalsOperator = "700000051000036108";

$unitRole = "UNIT"; # FIXME - this is a placeholder for a "has unit" role type to be created

# -------------------------------------------------------------------------------------------

# Determine which format, OWL or KRSS:
if ( $ARGV[0] eq "KRSS" ) {
	$dlformat = "KRSS";
}
elsif ( $ARGV[0] eq "OWL" ) {
	$dlformat = "OWL";
}
elsif ( $ARGV[0] eq "OWLF" ) {    # owl functional syntax
	$dlformat = "OWLF";
}
else { die "I don't recognize $ARGV[0]. Valid formats are KRSS, OWL, or OWLF.\n"; }

#-------------------------------------------------------------------------------
# Data Input
#-------------------------------------------------------------------------------
$conceptsFileName     = $ARGV[1];
$descriptionsFileName = $ARGV[2];
$statedRelsFileName   = $ARGV[3];
$concreteDomainsFileName   = $ARGV[4];

#-------------------------------------------------------------------------------
# File 1: The RF2 concepts table snapshot.
# Fields are: id[0], effectiveTime[1], active[2], moduleId[3], definitionStatusId[4]
#-------------------------------------------------------------------------------

open( CONCEPTS, $conceptsFileName ) || die "can't open $conceptsFileName";

# read input rows
while (<CONCEPTS>) {
	s/\015//g;
	s/\012//g;    # remove CR and LF characters
	@values = split( '\t', $_ );    # input file is tab delimited
	   # Filter out the header line, blank lines, and all inactive concepts
	   # NOTE : this updated version of the script no longer removes the metadata from the
	   # content - below used to say "&& ( $values[3] ne $metadataModuleId ) )" as well.
	   # This has been done because extension content may extend the metadata module
	   # content which causes metadata concepts to be included in the resultant file
	   # missing labels etc. As the metadata does no harm it has been included.
	if ( $values[0] && ( $values[2] eq "1") ) 
	{
	    my $primdefFlag = "1";
	    if ($values[4] eq $conceptDefinedId) { $primdefFlag = "0"; }
		$primitive{ $values[0] } = $primdefFlag;
	}
}
close(CONCEPTS);

#-------------------------------------------------------------------------------
# File 2: The RF2 descriptions table snapshot.
# Fields are: id[0], effectiveTime[1], active[2], moduleId[3], conceptId[4],
# languageCode[5], typeId[6], term[7], caseSignificanceId[8]
#-------------------------------------------------------------------------------

open( DESCRIPTIONS, $descriptionsFileName ) || die "can't open $descriptionsFileName";

# read input rows
while (<DESCRIPTIONS>) {
	s/\015//g;
	s/\012//g;    # remove CR and LF characters
	@values = split( '\t', $_ );    # input file is tab delimited
	   # Filter out the header line, blank lines
	if ( $values[0] && ( $values[2] eq "1") && ($values[6] eq $FSNId ) )
	{
		$fsn{ $values[4] } = &xmlify( $values[7] ); # xmlify changes & to &amp; < to &lt; > to &gt;
	}
}
close(DESCRIPTIONS);

#-------------------------------------------------------------------------------
# File 3: The RF2 stated relationships snapshot (object-attribute-value triples with role group numbers)
# Fields are: id[0], effectiveTime[1], active[2], modeuleId[3], sourceId[4], destinationId[5], 
# relationshipGroup[6], typeId[7], characteristicTypeId[8], modifierId[9]
#-------------------------------------------------------------------------------

# create %rels which is a hash that will contain all role relationships
# roles are initially read in and stored as triplets (attribute value rolegroup)

%rels = ();

# read in relationships table: relID con1 rel con2 characteristictype refinability roleGroup

open( RELATIONSHIPS, $statedRelsFileName )
  || die "can't open $statedRelsFileName";

while (<RELATIONSHIPS>) {
	s/\015//g;
	s/\012//g;
	@values = split( '\t', $_ );    # input file is tab delimited
	if ( $values[2] eq "1" ) # an active stated (defining) relationship -
	{                                
		if ( $values[7] eq $isaID ) {    # an is-a relationship
			&populateParent( $values[4], $values[5] );
			&populateChildren( $values[5], $values[4] );
		}
		else {    # a defining attribute-value relationship
			&populateRels( $values[0], $values[4], $values[7], $values[5], $values[6] );
		}
	}
}
close(RELATIONSHIPS);

#-------------------------------------------------------------------------------
# File 4: The RF2 concrete domains snapshot (CCS reference set)
# Fields are: id[0], effectiveTime[1], active[2], modeuleId[3], referenceSetId[4], referencedComponentId[5],
# unitId[6], operatorId[7], value[8]
#-------------------------------------------------------------------------------

# create %cds which is a hash that will contain all cd annotations
#

%cds = ();
%features = ();

open( CDS, $concreteDomainsFileName )
|| die "can't open $concreteDomainsFileName";

while (<CDS>) {
	s/\015//g;
	s/\012//g;
	@values = split( '\t', $_ );    # input file is tab delimited
	if ( $values[2] eq "1" ) # an active row
	{
       	&populateCDs( $values[5], $values[4], $values[7], $values[8], $values[6] );
       	
		if ( $measurementTypeFloat ~~ $parents{$values[4]} ) { # if its a measurement type float
			$features{ $values[4] } = "decimal";
		}
		elsif ( $measurementTypeInt ~~ $parents{$values[4]} ) { # if its a measurement type int
			$features{ $values[4] } = "integer";
		}
		else {
    		$features{ $values[4] } = undef;
		}
		
	}
}
close(CDS);




#-------------------------------------------------------------------------------
# File 4: The Output file
#-------------------------------------------------------------------------------
open( OUTF, ">$ARGV[5]" ) || die "can't open $ARGV[5]";

&populateRoles( $children{$conceptModelAttID}, "" );

if ( $dlformat eq "OWL" ) {    # OWL RDF/XML format output
	print OUTF "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
	print OUTF "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"\n";
	print OUTF "         xmlns:rdfs=\"http://www.w3.org/2000/01/rdf-schema#\"\n";
	print OUTF "         xmlns:xsd=\"http://www.w3.org/2001/XMLSchema#\"\n";
	print OUTF "         xmlns:owl=\"http://www.w3.org/2002/07/owl#\"\n";
	print OUTF "         xmlns=\"http://www.ihtsdo.org/\"\n";
	print OUTF "         xml:base=\"http://www.ihtsdo.org/\">\n\n";

	print OUTF "    <owl:Ontology rdf:about=\"\">\n";
	print OUTF "        <rdfs:label>SNOMED Clinical Terms, International Release, Stated Relationships in OWL RDF</rdfs:label>\n";
	print OUTF "        <owl:versionInfo>20120731</owl:versionInfo>\n";
	print OUTF "        <rdfs:comment>\n";
	print OUTF "Generated as OWL RDF/XML from SNOMED CT release files by Perl transform script\n";
	print OUTF "Input concepts file was             ", $conceptsFileName, "\n";
	print OUTF "Input stated relationships file was ", $statedRelsFileName, "\n";
	
    print OUTF "Copyright 2012 The International Health Terminology Standards Development Organisation (IHTSDO). ";
    print OUTF "All Rights Reserved. SNOMED CT was originally created by The College of American Pathologists. \\\"SNOMED\\\" and \\\"SNOMED CT\\\" ";
    print OUTF "are registered trademarks of the IHTSDO.  SNOMED CT has been created by combining SNOMED RT and a computer based nomenclature ";
    print OUTF "and classification known as Clinical Terms Version 3, formerly known as Read Codes Version 3, which was created on behalf of ";
    print OUTF "the UK Department of Health and is Crown copyright.  \n";
    print OUTF "This document forms part of the International Release of SNOMED CT distributed by the International Health Terminology ";
    print OUTF "Standards Development Organisation (IHTSDO), and is subject to the IHTSDO's SNOMED CT Affiliate Licence. ";
    print OUTF "Details of the SNOMED CT Affiliate Licence may be found at www.ihtsdo.org/our-standards/licensing/. \n";
    print OUTF "No part of this file may be reproduced or transmitted in any form or by any means, or stored in any kind of retrieval system, ";
    print OUTF "except by an Affiliate of the IHTSDO in accordance with the SNOMED CT Affiliate Licence. Any modification of this document ";
    print OUTF "(including without limitation the removal or modification of this notice) is prohibited without the express written permission ";
    print OUTF "of the IHTSDO.  Any copy of this file that is not obtained directly from the IHTSDO (or a Member of the IHTSDO) is not ";
    print OUTF "controlled by the IHTSDO, and may have been modified and may be out of date. Any recipient of this file who has received ";
    print OUTF "it by other means is encouraged to obtain a copy directly from the IHTSDO, or a Member of the IHTSDO. \n";
    print OUTF "(Details of the Members of the IHTSDO may be found at www.ihtsdo.org/members/).\n";
	
	print OUTF "        </rdfs:comment>\n";
	print OUTF "    </owl:Ontology>\n";
	print OUTF "<owl:ObjectProperty rdf:about=\"RoleGroup\">\n";
	print OUTF "    <rdfs:label xml:lang=\"en\">RoleGroup</rdfs:label>\n";
	print OUTF "</owl:ObjectProperty>\n";

	foreach $r1 ( sort keys %roles ) { &printroledefowl($r1); }

	foreach $c1 ( sort keys %primitive ) {
		&printconceptdefowl($c1) if ( not( $roles{$c1} ) );
	}

	print OUTF "</rdf:RDF>\n";

}
elsif ( $dlformat eq "OWLF" ) {    # OWL functional syntax output

	print OUTF "Prefix(xsd:=<http://www.w3.org/2001/XMLSchema#>)\n";
	print OUTF "Prefix(owl:=<http://www.w3.org/2002/07/owl#>)\n";
	print OUTF "Prefix(:=<http://www.ihtsdo.org/>)\n";	
	print OUTF "Prefix(xml:=<http://www.w3.org/XML/1998/namespace>)\n";
	print OUTF "Prefix(rdf:=<http://www.w3.org/1999/02/22-rdf-syntax-ns#>)\n";
	print OUTF "Prefix(rdfs:=<http://www.w3.org/2000/01/rdf-schema#>)\n";


	print OUTF "\n\nOntology(<http://www.ihtsdo.org>\n";
	print OUTF "Annotation(rdfs:label \"SNOMED Clinical Terms, International Release, Stated Relationships in OWL Functional Syntax\")\n";
	print OUTF "Annotation(owl:versionInfo \"20120731\")\n";
	print OUTF "Annotation(rdfs:comment \"\n";
	print OUTF "Generated as OWL Functional Syntax from SNOMED CT release files by Perl transform script.\n";
	print OUTF "Input concepts file was             ", $conceptsFileName, "\n";
	print OUTF "Input stated relationships file was ", $statedRelsFileName, "\n";
    print OUTF "Copyright 2012 The International Health Terminology Standards Development Organisation (IHTSDO). All Rights Reserved. SNOMED CT was originally created by The College of American Pathologists. \\\"SNOMED\\\" and \\\"SNOMED CT\\\" are registered trademarks of the IHTSDO.  SNOMED CT has been created by combining SNOMED RT and a computer based nomenclature and classification known as Clinical Terms Version 3, formerly known as Read Codes Version 3, which was created on behalf of the UK Department of Health and is Crown copyright.  \n";
	print OUTF "This document forms part of the International Release of SNOMED CT distributed by the International Health Terminology Standards Development Organisation (IHTSDO), and is subject to the IHTSDO's SNOMED CT Affiliate Licence. Details of the SNOMED CT Affiliate Licence may be found at www.ihtsdo.org/our-standards/licensing/. \n";
	print OUTF "No part of this file may be reproduced or transmitted in any form or by any means, or stored in any kind of retrieval system, except by an Affiliate of the IHTSDO in accordance with the SNOMED CT Affiliate Licence. Any modification of this document (including without limitation the removal or modification of this notice) is prohibited without the express written permission of the IHTSDO.  Any copy of this file that is not obtained directly from the IHTSDO (or a Member of the IHTSDO) is not controlled by the IHTSDO, and may have been modified and may be out of date. Any recipient of this file who has received it by other means is encouraged to obtain a copy directly from the IHTSDO, or a Member of the IHTSDO. \n";
	print OUTF "(Details of the Members of the IHTSDO may be found at www.ihtsdo.org/members/).\n";
	print OUTF "        \")\n";
	
    print OUTF "Declaration(ObjectProperty(:RoleGroup))\n";
    print OUTF "AnnotationAssertion(rdfs:label :RoleGroup \"RoleGroup\")\n";
	foreach $r1 ( sort keys %roles ) { &printroledefowlf($r1); }

	foreach $CD1 ( sort keys %features ) { &printCDdefowlf($CD1);}

	foreach $c1 ( sort keys %primitive ) {
		&printconceptdefowlf($c1) if ( not( $roles{$c1} ) );
	}

	print OUTF ")\n";

}
else {    # KRSS format output

	print OUTF "(define-primitive-role RoleGroup)\n";
	foreach $r1 ( sort keys %roles ) { &printroledefkrss($r1); }

	foreach $c1 ( sort keys %primitive ) {
		&printconceptdefkrss($c1) if ( not( $roles{$c1} ) );
	}
}

# =====================================================
# end of main program
# =====================================================

# =====================================================
# Subroutines
# =====================================================

sub xmlify {
	my ($fsnstring) = @_;
	if ( $dlformat eq "OWL") {    # xmlify the fsn for OWL RDF/XML outputs only
		$fsnstring =~ s/&/&amp;/g;
		$fsnstring =~ s/</&lt;/g;
		$fsnstring =~ s/>/&gt;/g;
	} elsif ( $dlformat eq "OWLF"){ # cannot use double quotes in the name
		$fsnstring =~ s/"/'/g;
	}
	return $fsnstring;
}

sub populateParent {
	my ( $c1, $c2 ) = @_;

	if ( $parents{$c1} ) {

		# parents is a hash containing a list of parents of the key
		push @{ $parents{$c1} }, $c2;
	}
	else {
		$parents{$c1} = [$c2];
	}

}

sub populateChildren {
	my ( $c1, $c2 ) = @_;

	if ( $children{$c1} ) {

		# children is a hash containing a list of children of the key
		push @{ $children{$c1} }, $c2;
	}
	else {
		$children{$c1} = [$c2];
	}

}

sub populateRels {
	my ( $comp, $c1, $rel, $c2, $rg ) = @_;

	#   print "populateRels: $c1, $rel, $c2, $rg\n";
	if ( $rels{$c1} ) {
		push @{ $rels{$c1} }, [ $comp, $rel, $c2, $rg ];
	}
	else {
		$rels{$c1} = [ [ $comp, $rel, $c2, $rg ] ];
	}
}

sub populateCDs {
	my ( $comp, $feature, $op, $value, $unit ) = @_;

	#   print "populateCDs: $comp, $feature, $op, $value, $unit\n";
	if ( $cds{$comp} ) {
		push @{ $cds{$comp} }, [ $feature, $op, $value, $unit ];
	}
	else {
		$cds{$comp} = [ [ $feature, $op, $value, $unit ] ];
	}
}

# --------------------------------------------------------------------------
# routines for handling role (attribute) definitions
# --------------------------------------------------------------------------

sub populateRoles
{ # in: a list of roles and their parent role id and name. out: $roles{$concept} is hash of roles
	my ( $roleListPtr, $parentSCTID ) = @_;
	my $role;
	foreach $role (@$roleListPtr) {
		if ( $children{$role} ) {
			&populateRoles( $children{$role}, $role );
		}
		if ( $rightid{$role} ) {
			&populateRoleDef( $role, $fsn{$role}, $rightid{$role},
				$parentSCTID );
		}
		else {
			&populateRoleDef( $role, $fsn{$role}, "", $parentSCTID );
		}
	}
}

sub populateRoleDef {    # assumes at most one rightID, at most one parentrole.
	my ( $code, $name, $rightID, $parentrole ) = @_;
	$roles{$code}{'name'}       = $name;
	$roles{$code}{'rightID'}    = $rightID;
	$roles{$code}{'parentrole'} = $parentrole;
}

sub printroledefowl {    # print object properties of OWL RDF/XML syntax
	my ($r1) = @_;
	if ( $roles{$r1}{'parentrole'} eq "" ) {   # if there is no parent role specified
		print OUTF "<owl:ObjectProperty rdf:about=\"SCT_", $r1, "\">\n";
		print OUTF "    <rdfs:label xml:lang=\"en\">", $fsn{$r1}, "</rdfs:label>\n";
		print OUTF "</owl:ObjectProperty>\n";
	}
	else {
		print OUTF "<owl:ObjectProperty rdf:about=\"SCT_", $r1, "\">\n";
		print OUTF "    <rdfs:label xml:lang=\"en\">", $fsn{$r1}, "</rdfs:label>\n";
		print OUTF "    <rdfs:subPropertyOf rdf:resource=\"SCT_", $roles{$r1}{'parentrole'}, "\"/>\n";
		print OUTF "</owl:ObjectProperty>\n";
	}
	unless ( $roles{$r1}{'rightID'} eq "" ) {    # unless there is no right identity
		print OUTF "<rdf:Description>\n";
		print OUTF "   <rdfs:subPropertyOf rdf:resource=\"SCT_", $r1, "\"/>\n";
		print OUTF "   <owl:propertyChain rdf:parseType=\"Collection\">\n";
		print OUTF "      <rdf:Description rdf:about=\"SCT_", $r1, "\"/>\n";
		print OUTF "      <rdf:Description rdf:about=\"SCT_", $roles{$r1}{'rightID'}, "\"/>\n";
		print OUTF "   </owl:propertyChain>\n";
		print OUTF "</rdf:Description>\n";
	}
}

sub printroledefowlf {    # print object properties of OWL functional syntax
	my ($r1) = @_;
	print OUTF "Declaration(ObjectProperty(:SCT_",      $r1, "))\n";
	print OUTF "AnnotationAssertion(rdfs:label :SCT_", $r1, " \"",  $fsn{$r1}, "\")\n";
	unless ( $roles{$r1}{'parentrole'} eq "" ) {   # unless there is no parent role specified
		print OUTF "SubObjectPropertyOf(:SCT_", $r1, " :SCT_", $roles{$r1}{'parentrole'}, ")\n";
	}
	unless ( $roles{$r1}{'rightID'} eq "" ) {      # unless there is no right identity
		print OUTF "SubObjectPropertyOf(ObjectPropertyChain(:SCT_", $r1, " :SCT_", $roles{$r1}{'rightID'}, ") :SCT_", $r1, ")\n";
	}
}

sub printCDdefowlf {    # print object properties of OWL functional syntax
	my ($CD1) = @_;
		
	print OUTF "Declaration(DataProperty(:SCT_",      $CD1, "))\n";
	print OUTF "AnnotationAssertion(rdfs:label :SCT_", $CD1, " \"",  $fsn{$CD1}, "\")\n";
	
	if ( defined $features{$CD1} ) {
		print OUTF "DataPropertyRange(:SCT_", $CD1, " xsd:", $features{$CD1}, ")\n";
	} else {
		print "WARNING: Unsure of data property range for ", $CD1, " | ", $fsn{$CD1}, " | - none defined \n";
	}
}

sub printroledefkrss {
	my ($r1) = @_;
	print OUTF "(define-primitive-role SCT_$r1";
	unless ($roles{$r1}{'parentrole'} eq "") { # unless there is no parent role specified
		print OUTF " :parent SCT_$roles{$r1}{'parentrole'}";
	} 
	unless ( $roles{$r1}{'rightID'} eq "" ) {      # unless there is no right identity
        # This uses the extended KRSS syntax accepted by the CEL classifier
		print OUTF " :right-identity SCT_$roles{$r1}{'rightID'}";
	}
    print OUTF ")\n";
}

# --------------------------------------------------------------------------

sub printconceptdefowl {
	my ($c1) = @_;
	if ( $parentpointer = $parents{$c1} ) {
		$nparents = @$parentpointer;
	}
	else { $nparents = 0; }
	if ( $rels{$c1} ) { $nrels = 1; }
	else { $nrels = 0; }
	$nelements = $nparents + $nrels;
	print OUTF "<owl:Class rdf:about=\"SCT_", $c1, "\">\n";
	print OUTF "   <rdfs:label xml:lang=\"en\">", $fsn{$c1}, "</rdfs:label>\n";
    if ($nelements == 0 ) { # no parent, therefore a top level node. 
	    print OUTF "</owl:Class>\n";
	} elsif ( $nelements == 1 ) {
		print OUTF "    <rdfs:subClassOf rdf:resource=\"SCT_", $parents{$c1}[0], "\"/>\n";
		print OUTF "</owl:Class>\n";
	} else { # more than one defining element; may be primitive or sufficiently defined
			if ( $primitive{$c1} eq "1" ) {    # use subClassOf
			    print OUTF "    <rdfs:subClassOf><owl:Class>\n";
			} else { # Fully defined. Use equivalentClass
		        print OUTF "    <owl:equivalentClass><owl:Class>\n";
			}
			print OUTF "   <owl:intersectionOf rdf:parseType=\"Collection\">\n";
			foreach $parentc ( @{ $parents{$c1} } ) {
				print OUTF "       <owl:Class rdf:about=\"SCT_", $parentc, "\"/>\n";
			}
			unless ( $nrels == 0 ) {
				foreach $rgptr ( @{ &grouproles( $rels{$c1} ) } ) {
					&printrolegroupowl($rgptr);
				}
			}
			print OUTF "   </owl:intersectionOf>\n";
			if ($primitive{$c1} eq "1") {
				print OUTF "   </owl:Class></rdfs:subClassOf>\n";
			} else {
				print OUTF "   </owl:Class></owl:equivalentClass>\n";
			}
			print OUTF "</owl:Class>\n";
	}
}


sub printconceptdefowlf {
	my ($c1) = @_;
	if ( $parentpointer = $parents{$c1} ) {
		$nparents = @$parentpointer;
	}
	else { $nparents = 0; }
	if ( $rels{$c1} ) { $nrels = 1; }
	else { $nrels = 0; }
	if ( $cds{$c1} ) { $ncds = 1; }
	else { $ncds = 0; }
	$nelements = $nparents + $nrels + $ncds;
	print OUTF "Declaration(Class(:SCT_", $c1, "))\nAnnotationAssertion(rdfs:label :SCT_", $c1, " \"", $fsn{$c1}, "\")\n";

	    if ($nelements == 0 ) { # no parent, therefore a top level node. No need to give SubClassOf to owl:Thing, that will happen automatically.
#	    	no-op
	    } elsif ( $nelements == 1 ) {
			print OUTF "SubClassOf(:SCT_", $c1, " :SCT_", $parents{$c1}[0], ")\n";
		} else { # more than one defining element; may be primitive or sufficiently defined
			if ( $primitive{$c1} eq "1" ) {    # use subClassOf
			   print OUTF "SubClassOf(:SCT_", $c1, " ObjectIntersectionOf(";
			} else {
			   print OUTF "EquivalentClasses(:SCT_", $c1, " ObjectIntersectionOf(";	
			}
            # output explicit parents
			foreach $parentc ( @{ $parents{$c1} } ) {
				print OUTF ":SCT_", $parentc, " ";
			}
			print OUTF "\n";
            # output explicit cd info
			foreach $datatype ( @{ $cds{$c1} } ) {
				print OUTF " ", &mapdatatypef( $datatype );
			}
			print OUTF "\n";
			unless ( $nrels == 0 ) {
				foreach $rgptr ( @{ &grouproles( $rels{$c1} ) } ) {
					&printrolegroupowlf($rgptr);
				}
			}
			print OUTF "))\n";
		}
}

sub mapdatatypef {
    my ($ptr) = @_;
    $feature = $ptr->[0];
    $op = $ptr->[1];
    $value = $ptr->[2];
    $unit = $ptr->[3];

	

	# NOTE: this only works for equality at present. If other operators are provided this section will
	# require more work to generate the correct OWLF for the operators.
    if ($op eq $equalsOperator) {
        return "ObjectSomeValuesFrom(:RoleGroup ObjectIntersectionOf(ObjectSomeValuesFrom(:SCT_$unitRole :SCT_$unit ) DataHasValue(:SCT_$feature \"$value\"^^xsd:" . $features{$feature} . " )))";
    } else { die "Unexpected op: $op\n"; }

}

sub printrolegroupowl {
	local ($rgrp) = @_;
	$ngrps = @$rgrp;
	if ( $ngrps > 1 ) {

		print OUTF "       <owl:Restriction>\n";
		print OUTF "            <owl:onProperty rdf:resource=\"RoleGroup\"/>\n";
		print OUTF "            <owl:someValuesFrom>\n";
		print OUTF "                <owl:Class>\n";
		print OUTF
		  "                <owl:intersectionOf rdf:parseType=\"Collection\">\n";
		foreach $grp (@$rgrp) {    # multiple attributes nested under RoleGroup
			print OUTF "                    <owl:Restriction>\n";
			print OUTF "                        <owl:onProperty rdf:resource=\"SCT_", $$grp[0], "\"/>\n";
			print OUTF "                        <owl:someValuesFrom rdf:resource=\"SCT_", $$grp[1], "\"/>\n";
			print OUTF "                    </owl:Restriction>\n";
		}
		print OUTF "                </owl:intersectionOf>\n";
		print OUTF "                </owl:Class>\n";
		print OUTF "            </owl:someValuesFrom>\n";
		print OUTF "       </owl:Restriction>\n";

	}
	else {    # only one group.  No need for intersectionOf or looping.
		if ( $nevergrouped{ $$rgrp[0][0] } ) {    # no need for RoleGroup
			print OUTF "       <owl:Restriction>\n";
			print OUTF "           <owl:onProperty rdf:resource=\"SCT_", $$rgrp[0][0], "\"/>\n";
			print OUTF "           <owl:someValuesFrom rdf:resource=\"SCT_", $$rgrp[0][1], "\"/>\n";
			print OUTF "       </owl:Restriction>\n";
		}
		else {    # single attribute nested under RoleGroup
			print OUTF "       <owl:Restriction>\n";
			print OUTF "            <owl:onProperty rdf:resource=\"RoleGroup\"/>\n";
			print OUTF "            <owl:someValuesFrom>\n";
			print OUTF "                <owl:Restriction>\n";
			print OUTF "                    <owl:onProperty rdf:resource=\"SCT_", $$rgrp[0][0], "\"/>\n";
			print OUTF "                    <owl:someValuesFrom rdf:resource=\"SCT_", $$rgrp[0][1], "\"/>\n";
			print OUTF "                </owl:Restriction>\n";
			print OUTF "            </owl:someValuesFrom>\n";
			print OUTF "       </owl:Restriction>\n";
		}
	}
}

sub printrolegroupowlf {
	local ($rgrp) = @_;
	$ngrps = @$rgrp;
    
	if ( $ngrps > 1 ) {
		print OUTF "       ObjectSomeValuesFrom(:RoleGroup ObjectIntersectionOf(\n";
		foreach $grp (@$rgrp) {
        		$str = &resolvef($$grp[1], $$grp[2]);
			print OUTF "                        ObjectSomeValuesFrom(:SCT_$$grp[0] $str)\n";
		}
		print OUTF "))";
	}
	else {    # only one group. No need for intersectionOf or looping.
        	$str = &resolvef($$rgrp[0][1], $$rgrp[0][2]);
		if ( $nevergrouped{ $$rgrp[0][0] } ) {    # No need for RoleGroup
			print OUTF "       ObjectSomeValuesFrom(:SCT_$$rgrp[0][0] $str)\n";
		}
		else {
			print OUTF "       ObjectSomeValuesFrom(:RoleGroup ObjectSomeValuesFrom(:SCT_$$rgrp[0][0] $str))\n";
		}
	}
}

sub resolvef {
    my ($value, $comp) = @_;
    
    if ( $cds{$comp} ) {
        $result = ":SCT_$value";
        foreach $datatype (@{ $cds{$comp} }) {
            $result = "$result " . &mapdatatypef($datatype);
        }
        return "ObjectIntersectionOf( $result )";
    } else {
        return ":SCT_$value";
    }
}

sub printconceptdefkrss {
	my ($c1) = @_;
	if ( $parentpointer = $parents{$c1} ) {
		$nparents = @$parentpointer;
	}
	else { $nparents = 0; }
	if ( $rels{$c1} ) { $nrels = 1; }
	else { $nrels = 0; }
	$nelements = $nparents + $nrels;

	if ( $primitive{$c1} eq "1" ) {    # primitive, use define-primitive-concept
		if ( $nparents eq 0 ) {
			print OUTF "(define-primitive-concept SCT_$c1)\n";
		}
		elsif ( ( $nparents eq 1 ) && ( $nelements eq 1 ) )
		{                              # primitive defined by a single parent
			print OUTF "(define-primitive-concept SCT_$c1 SCT_$parents{$c1}[0])\n";
		}
		else {
			print OUTF "(define-primitive-concept SCT_$c1 (and \n";
			foreach $parentc ( @{ $parents{$c1} } ) {
				print OUTF "   SCT_$parentc\n";
			}
			unless ( $nrels == 0 ) {
				foreach $rgptr ( @{ &grouproles( $rels{$c1} ) } ) {
					&printrolegroupkrss($rgptr);
				}
			}
			print OUTF "))\n";
		}
	}
	else {    #  sufficiently defined, use define-concept
		print OUTF "(define-concept SCT_$c1 (and\n";
		if ( $nelements > 1 ) {
			foreach $parentc ( @{ $parents{$c1} } ) {
				print OUTF "        SCT_$parentc\n";
			}
			unless ( $nrels == 0 ) {
				foreach $rgptr ( @{ &grouproles( $rels{$c1} ) } ) {
					&printrolegroupkrss($rgptr);
				}
			}
			print OUTF "))\n";
		}
		else {
			print ">>>> error >>>> nelements not > 1 for fully defined $c1\n";
		}
	}
}

sub printrolegroupkrss {
	local ($rgrp) = @_;
	$ngrps = @$rgrp;
	if ( $ngrps > 1 ) {
		print OUTF "       (some RoleGroup (and \n";
		foreach $grp (@$rgrp) {
			print OUTF "                        (some SCT_$$grp[0] SCT_$$grp[1] )\n";
		}
		print OUTF "                        )\n";
		print OUTF "        )\n";
	}
	else {    # only one group. No need for intersectionOf or looping.
		if ( $nevergrouped{ $$rgrp[0][0] } ) {    # No need for RoleGroup
			print OUTF "       (some SCT_$$rgrp[0][0] SCT_$$rgrp[0][1] )\n";
		}
		else {
			print OUTF "       (some RoleGroup (some SCT_$$rgrp[0][0] SCT_$$rgrp[0][1] ))\n";
		}
	}
}

#-------------------------------------------------------------------------------
# grouproles
#-------------------------------------------------------------------------------
# Changes its rels from a list of triplets <role value groupnum>
# into a list of rolegroups, each of which is a list of <role value comp> triples.
# The purpose is to eliminate role group "numbers"
# The role group as a list of att-val-comp triples preserves role groups independent of the groupnum
#-------------------------------------------------------------------------------

sub grouproles
{    # takes a list of role quads (component attribute value rolegroup-number)
	    # returns a list of rolegroups, which are lists of (attr value component) triples
	local ($rolesptr) = @_;
	my ( $role, $resultptr, $groupptr, %rgrp, $attr, $val, $grp );
	foreach $role (@$rolesptr) {    # $role is a pointer to a quad
        $comp = $role->[0];
		$attr = $role->[1];
		$val  = $role->[2];
		$grp  = $role->[3];
        
		if ( $rgrp{$grp} ) { # if group number $grp has been encountered already
			    # change quad into a triplet and add to existing list of triples
			push @{ $rgrp{$grp} }, [ $attr, $val, $comp ];
		}
		else {    # new list of triples
			$rgrp{$grp} = [ [ $attr, $val, $comp ] ];
		}
	}
	@$resultptr = ();

	# @$groupptr is a list of triples belonging to one group
	while ( ( $key, $groupptr ) = each %rgrp ) {
		if ( $key eq "0" ) {

			# group 0 indicates a single att-val-comp triple with no other triples
			foreach $tripleptr (@$groupptr) {

				# a list of pairs with only one pair
				push @$resultptr, [ [ $tripleptr->[0], $tripleptr->[1], $tripleptr->[2] ] ];
			}
		}
		else {
			push @$resultptr, [@$groupptr];    # a list of triples
		}
	}
	return ($resultptr);
}

