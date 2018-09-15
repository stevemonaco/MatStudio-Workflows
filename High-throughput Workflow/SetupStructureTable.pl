#!perl
# Author: Steve Monaco
# Materials Studio 2017 R2
# SetupStructureTable v1.01
#
# Description: Builds study tables from structures contained in a specified
#   directory on disk. Obtains structural information (cell lengths, angles,
#   etc). Output tables can be used for high throughput geometry optimization
#   and property calculations with the CalculateStructureTable script.
#
# Run: Install as a Materials Studio script library and run locally.
################################################################################

use strict;
use Getopt::Long;
use Math::Trig;
use MaterialsScript qw(:all);

######################################################################
# User Menu variables
my %Args;
GetOptions(\%Args, "Table_Prefix_Name=s", "Path_To_Structures=s", "Structures_Per_Table=i", "Crystal_Settings_Name=s", "MIB_Settings_Name=s", "Create_MIB_Table=s", "MIB_Nearest_Neighbor_Distance=f");

my $TablePrefixName = $Args{Table_Prefix_Name}; # eg. "Alkanes" -> Alkanes.001.std, Alkanes.002.std, etc.
my $PathToStructures = $Args{Path_To_Structures}; # Path to folder of structures, absolute to project root. eg "C:\Chemistry\MSProject_Files\InputDataSet\"
my $StructuresPerTable = $Args{Structures_Per_Table}; # Number of structures to add per table, 0 to add all to the same table
my $CrystalSettingsName = $Args{Crystal_Settings_Name}; # Name of the settings file for crystal calculation. eg "PAHOpt"
my $MIBSettingsName = $Args{MIB_Settings_Name}; # Name of the settings file for MIB calculation. eg "MolOpt"
my $CreateMIBTable = $Args{Create_MIB_Table}; # Yes/no decision to create a study table with MIB structures
my $MIBNearestNeighborDistance = $Args{MIB_Nearest_Neighbor_Distance}; # Distance to nearest neighboring molecule. eg. 20.0
#######################################################################

my $tablecount = 1; # Number of tables created thusfar
my $row = 0; # Row to populate in the current table
my $module = Modules->CASTEP;
my $pathname = sprintf("%s.%03d", $TablePrefixName, $tablecount);

my $primarytable = SetupNewStudyTable(sprintf("%s\\%s.std", $pathname, $pathname), 1);
my $mibtable;
if($CreateMIBTable)
{
	$mibtable = SetupNewStudyTable(sprintf("%s\\%s.Mol.std", $pathname, $pathname), 1);
}

CopySettings($CrystalSettingsName, sprintf("%s\\%s", $pathname, $CrystalSettingsName));
CopySettings($MIBSettingsName, sprintf("%s\\%s", $pathname, $MIBSettingsName));

opendir(filesdirectory, $PathToStructures);
my @files = readdir(filesdirectory);

foreach my $file(@files)
{
	next if $file =~ m/^\.$/; # skip .
	next if $file =~ m/^\.\.$/; # skip ..
	next if $file !~ m/(.xsd|.cif|.mol)/; # Skip if the file is not an .xsd, .cif, or .mol structure
	
	print $file . "\n";

	$primarytable->InsertFrom($PathToStructures . $file);
	my $inputdoc = $primarytable->Cell($row, 0);
	
	print "Adding props for " . $inputdoc->Name . "\n";
	$primarytable->Cell($row, 1) = $inputdoc->SymmetryDefinition->LengthA;
	$primarytable->Cell($row, 2) = $inputdoc->SymmetryDefinition->LengthB;
	$primarytable->Cell($row, 3) = $inputdoc->SymmetryDefinition->LengthC;
	$primarytable->Cell($row, 4) = $inputdoc->SymmetryDefinition->AngleAlpha;
	$primarytable->Cell($row, 5) = $inputdoc->SymmetryDefinition->AngleBeta;
	$primarytable->Cell($row, 6) = $inputdoc->SymmetryDefinition->AngleGamma;
	$primarytable->Cell($row, 7) = $inputdoc->SymmetrySystem->Density;
	$primarytable->Cell($row, 8) = $inputdoc->Lattice3D->CellVolume;
	$primarytable->Cell($row, 9) = $inputdoc->SymmetryDefinition->Name . " [" . $inputdoc->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
	
	if($CreateMIBTable)
	{
		my $mibdoc = UnpackCrystal($inputdoc, $MIBNearestNeighborDistance);
		$mibtable->Cell($row, 0) = $mibdoc;
		$mibtable->Cell($row, 1) = $mibdoc->SymmetryDefinition->LengthA;
		$mibtable->Cell($row, 2) = $mibdoc->SymmetryDefinition->LengthB;
		$mibtable->Cell($row, 3) = $mibdoc->SymmetryDefinition->LengthC;
		$mibtable->Cell($row, 4) = $mibdoc->SymmetryDefinition->AngleAlpha;
		$mibtable->Cell($row, 5) = $mibdoc->SymmetryDefinition->AngleBeta;
		$mibtable->Cell($row, 6) = $mibdoc->SymmetryDefinition->AngleGamma;
		$mibtable->Cell($row, 7) = $mibdoc->SymmetrySystem->Density;
		$mibtable->Cell($row, 8) = $mibdoc->Lattice3D->CellVolume;
		$mibtable->Cell($row, 9) = $mibdoc->SymmetryDefinition->Name . " [" . $mibdoc->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
		$mibdoc->Discard;
	}
	
	$inputdoc->Discard;
	$row++;
	
	if($row >= $StructuresPerTable and $StructuresPerTable != 0) # Create next table in the series
	{
		$primarytable->Save;
		$primarytable->Close;
		$mibtable->Save;
		$mibtable->Close;
		$tablecount++;
		$row = 0;
		
		$pathname = sprintf("%s.%03d", $TablePrefixName, $tablecount);
		$primarytable = SetupNewStudyTable(sprintf("%s\\%s.std", $pathname, $pathname), 1);
		if($CreateMIBTable)
		{
			$mibtable = SetupNewStudyTable(sprintf("%s\\%s.Mol.std", $pathname, $pathname), 1);
		}
		
		CopySettings($CrystalSettingsName, sprintf("%s\\%s", $pathname, $CrystalSettingsName));
		CopySettings($MIBSettingsName, sprintf("%s\\%s", $pathname, $MIBSettingsName));
	}
}
$primarytable->Close;
if($CreateMIBTable)
{
	$mibtable->Close;
}

################################################################################
# Creates a new study table, sets up the appropriate column headers, and resizes
sub SetupNewStudyTable()
{
	my ($stdname, $addstructuralproperties) = @_;
	
	my $std = Documents->New($stdname);
	my $sheet = $std->ActiveSheet;
	$sheet->InsertColumn(0, "Structure");
	my $cols = 1;
	
	if($addstructuralproperties)
	{
		$sheet->InsertColumn(1, "a");
		$sheet->InsertColumn(2, "b");
		$sheet->InsertColumn(3, "c");
		$sheet->InsertColumn(4, "alpha");
		$sheet->InsertColumn(5, "beta");
		$sheet->InsertColumn(6, "gamma");
		$sheet->InsertColumn(7, "Density");
		$sheet->InsertColumn(8, "Volume");
		$sheet->InsertColumn(9, "Symmetry");
		$cols = $cols + 9;
	}
	
	# Delete all blank rows and columns from the table
	for(my $i = $sheet->RowCount - 1; $i >= 1; $i--)
	{
		$sheet->DeleteRow($i);
	}
	for(my $i = $sheet->ColumnCount - 1; $i >= $cols; $i--)
	{
		$sheet->DeleteColumn($i);
	}
	
	return $std;
}

################################################################################
# Copies a settings file from one location to another
sub CopySettings()
{
	my ($srcname, $destname) = @_;
	
	if($srcname ne "")
	{	
		$module->ResetSettings;
		$module->LoadSettings($srcname);
		$module->SaveSettings($destname);
	}
}

################################################################################
# Creates a molecule-in-a-box XSD from a crystal XSD
# $padding - Distance to the molecule's nearest neighbor in angstroms
sub UnpackCrystal()
{
    my ($inputdoc, $padding) = @_;
    
    my $output = Documents->New($inputdoc->Name . ".Mol.xsd");
	$output->Name = $inputdoc->Name . ".Mol";
    
    my $atoms = $inputdoc->AsymmetricUnit->Atoms->Item(1)->Fragment->Atoms;
    my $mol;

    if($atoms->Count == 0)
    {
        die("No atoms found in structure");
    }
    else
    {
        $mol = $atoms->Item(1)->Fragment;
    }

    $output->CopyFrom($mol);
    $mol = $output->Atoms;

    # Translate the molecule's centroid to the origin.
    my $centroid = $output->CreateCentroid($mol);
    $centroid->IsWeighted = "No"; # Geometric midpoint
    $mol->Translate(Point( X => -$centroid->CentroidXYZ->X, Y => -$centroid->CentroidXYZ->Y, Z => -$centroid->CentroidXYZ->Z ));
    $centroid->Delete();

    # Create the principal axes
    my $axes = $output->CreatePrincipalAxes($mol);
    $axes->IsWeighted = "No";

    # Rotate principle axes so they align with the document's axes
    my $pa1 = $axes->PrincipalAxis1; # Longest axis
    my $angle = rad2deg(acos_real($pa1->X));
    my $rotationaxis = Point(X=>0, Y=>$pa1->Z, Z=>-$pa1->Y);
    $mol->RotateAboutPoint($angle, $rotationaxis, $axes->CentroidXYZ);

    my $pa2 = $axes->PrincipalAxis2;
    $angle = rad2deg(acos_real($pa2->Y));
    my $rotationaxis = Point(X=>-$pa2->Z , Y=>0, Z=>$pa2->X );
    $mol->RotateAboutPoint($angle, $rotationaxis, $axes->CentroidXYZ);
    $axes->Delete();

    # Create a bounding box which is minimum containment size for atoms and their vdW radius
    (my $xmin, my $xmax, my $ymin, my $ymax, my $zmin, my $zmax) = BoundingBox($mol);

    # Build a P1 crystal and enlarge the bounding box
    Tools->CrystalBuilder->SetSpaceGroup("P1", "");
    my $width = ($xmax - $xmin) + $padding;
    my $height = ($ymax - $ymin) + $padding;
    my $depth = ($zmax - $zmin) + $padding;

    Tools->CrystalBuilder->SetCellParameters($width, $height, $depth, 90, 90, 90);
    Tools->CrystalBuilder->Build($mol);

    # Reposition a molecule to the box's center and rebuild crystal
    $mol->Translate(Point(X => $width / 2, Y => $height / 2, Z => $depth / 2 ));
    Tools->Symmetry->UnbuildCrystal($output);
    Tools->CrystalBuilder->Build($output);

	return $output;
}



################################################################################
# Angle = arccos ((a dot b) / (|a| * |b|)) * (pi / 180)
# Where dot is the dot product and |a| is the magnitude (or "norm") of a
# Returns angle in degrees
sub FindAngleBetweenTwoVectors()
{
    my ($a, $b) = @_;
    my $dot = $a->X * $b->X + $a->Y * $b->Y + $a->Z * $b->Z;
    my $amagnitude = sqrt($a->X * $a->X + $a->Y * $a->Y + $a->Z * $a->Z);
    my $bmagnitude = sqrt($b->X * $b->X + $b->Y * $b->Y + $b->Z * $b->Z);
    
    my $angle = $dot / ($amagnitude * $bmagnitude);
    
    return (180 / pi) * acos($angle);
}

################################################################################
# (a, b, c) = A x B
# Returns cross-product of two unit 3D vectors
# A x B = i(AyBz - AzBy) - j(AxBz - AzBx) + k(AxBy - AyBx)
sub FindCrossProduct()
{
    my ($A, $B) = @_;
    my $i = $A->Y * $B->Z - $A->Z * $B->Y;
    my $j = -($A->X * $B->Z - $A->Z * $B->X);
    my $k = $A->X * $B->Y - $A->Y * $B->X;
    return ($i, $j, $k);
}

################################################################################
# Returns coordinates for a minimum, rectangular bounding box
# (no parallelepipeds), given a list of atoms

sub BoundingBox()
{
    my ($atoms) = @_;
    my $xmin, my $xmax, my $ymin, my $ymax, my $zmin, my $zmax;
    
    foreach my $atom (@$atoms)
    {
        if($atom->X< $xmin)
        {
            $xmin = $atom->X;
        }
        if($atom->X > $xmax)
        {
            $xmax = $atom->X;
        }
        if($atom->Y < $ymin)
        {
            $ymin = $atom->Y;
        }
        if($atom->Y > $ymax)
        {
            $ymax = $atom->Y;
        }
        if($atom->Z < $zmin)
        {
            $zmin = $atom->Z;
        }
        if($atom->Z > $zmax)
        {
            $zmax = $atom->Z;
        }
    }
    
    return ($xmin, $xmax, $ymin, $ymax, $zmin, $zmax);
}