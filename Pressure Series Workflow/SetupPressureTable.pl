#!perl
#
# Input: Initial structure for pressure series
#
# Steve Monaco
# Materials Studio 6.0
# SetupPressureTable v1.1
#
# v1.1 - Adds column for band gap
#
################################################################################

use strict;
use Getopt::Long;
use MaterialsScript qw(:all);

my %Args;
GetOptions(\%Args, "InitialPressure=f", "FinalPressure=f", "Delta=f", "IsExperimental=s");

######################################################################
# User-defined variables

my $inputdoc = Documents->ActiveDocument;
my $InitialPressure = $Args{InitialPressure};
my $FinalPressure = $Args{FinalPressure};
my $Delta = $Args{Delta};
my $IsExperimental = $Args{IsExperimental};

######################################################################

# Create new table
my $table = Documents->New($inputdoc->Name . ".std");
my $sheet = $table->ActiveSheet;
my $row = 0;

# Always using the conventional cell representation
$inputdoc->ConventionalCell;

# Setup column headings
$sheet->InsertColumn(0, "Structure");
$sheet->InsertColumn(1, "Pressure (GPa)");
$sheet->InsertColumn(2, "a");
$sheet->InsertColumn(3, "b");
$sheet->InsertColumn(4, "c");
$sheet->InsertColumn(5, "alpha");
$sheet->InsertColumn(6, "beta");
$sheet->InsertColumn(7, "gamma");
$sheet->InsertColumn(8, "Density");
$sheet->InsertColumn(9, "Volume");
$sheet->InsertColumn(10, "Symmetry");
$sheet->InsertColumn(11, "BandGap");
$sheet->InsertColumn(12, "Optimized?");

# Add initial structure's data to the table
$table->Cell($row, 0) = $inputdoc;
$table->Cell($row, 2) = $inputdoc->SymmetryDefinition->LengthA;
$table->Cell($row, 3) = $inputdoc->SymmetryDefinition->LengthB;
$table->Cell($row, 4) = $inputdoc->SymmetryDefinition->LengthC;
$table->Cell($row, 5) = $inputdoc->SymmetryDefinition->AngleAlpha;
$table->Cell($row, 6) = $inputdoc->SymmetryDefinition->AngleBeta;
$table->Cell($row, 7) = $inputdoc->SymmetryDefinition->AngleGamma;
$table->Cell($row, 8) = $inputdoc->SymmetrySystem->Density;
$table->Cell($row, 9) = $inputdoc->Lattice3D->CellVolume;
$table->Cell($row, 10) = $inputdoc->SymmetryDefinition->Name . " [" . $inputdoc->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
$table->Cell($row, 11) = ""; # Leave band gap blank
$table->Cell($row, 12) = "Yes";

my $i;
if($IsExperimental eq "Yes")
{
	$table->Cell($row, 1) = "Experimental - " . $InitialPressure;
	$i = $InitialPressure;
}
else
{
	$table->Cell($row, 1) = $InitialPressure;
	$i = $InitialPressure + $Delta;
}
$row++;

# Setup the rest of the table
for($i; $i <= $FinalPressure; $i = $i + $Delta)
{
	$table->Cell($row, 1) = $i;
	$table->Cell($row, 12) = "No";
	$row++;
}

# Delete all blank rows and columns from the table
for($i = $sheet->RowCount - 1; $i >= $row; $i--)
{
	$sheet->DeleteRow($i);
}
for($i = $sheet->ColumnCount - 1; $i > 12; $i--)
{
	$sheet->DeleteColumn($i);
}

$table->Save;