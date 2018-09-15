#!perl
#
# Input: Study table generated by SetupStructureTable
# Author: Steve Monaco
# Materials Studio 2017 R2
# CalculateStructureTable v1.01
#
# Description: Performs a calculation on each structure in the active study
#   table and optionally retrieves results. Can also create a MIB structure
#   table from the result of the first calculation, perform a secondary
#   calculation provided by the user, and retrieve results. Note that the
#   properties retrieved must be present for -both- the primary and secondary
#   calculations.
#
# Change log:
# v1.01 - Fixed parameters
#       - TODO: Fail softly on failure to open files
#       - TODO: Fix importing of csd cifs
################################################################################

use strict;
use Getopt::Long;
use Cwd qw(cwd);
use Math::Trig;
use File::Spec qw(:all);
use List::Util qw(min max);
use MaterialsScript qw(:all);

################################################################################
# User Menu variables
my %Args;
GetOptions(\%Args, "Perform_Geometry_Optimization=s", "Retrieve_Band_Structure=s", "Retrieve_Polarizability=s", "Primary_Settings_Name=s",
            "Perform_Secondary_MIB_Calculation=s", "MIB_Nearest_Neighbor_Distance=f", "Secondary_MIB_Settings_Name=s");

my $InputTable = Documents->ActiveDocument;
my $PerformGeometryOptimization = $Args{Perform_Geometry_Optimization};
my $RetrieveBandStructure = $Args{Retrieve_Band_Structure};
my $RetrievePolarizability = $Args{Retrieve_Polarizability};
my $PrimarySettingsName = $Args{Primary_Settings_Name};
my $PerformSecondaryMIBCalculation = $Args{Perform_Secondary_MIB_Calculation};
my $MIBNearestNeighborDistance = $Args{MIB_Nearest_Neighbor_Distance};
my $SecondaryMIBSettingsName = $Args{Secondary_MIB_Settings_Name};

################################################################################

my $MaxTries = 3; # Maximum number of retries if a calculation fails
local $| = 1; # Automatically flush script output to stdout
my $rootdir = cwd;
my $calctable = Documents->New($InputTable->Name . "." . $PrimarySettingsName . ".std");
my $mibtable;
my $module = Modules->CASTEP;
SetupTableHeaders($calctable);

if($PerformSecondaryMIBCalculation eq "Yes")
{
	$mibtable = Documents->New($InputTable->Name . "." . $SecondaryMIBSettingsName . ".std");
	SetupTableHeaders($mibtable);
}

# Run calculations on each structure in the study table
for(my $i = $0; $i < $InputTable->RowCount; $i++)
{
	my $source = $InputTable->Cell($i, 0); # Retrieve the source structure from the first column
	my $structure = Documents->New($source->Name . ".xsd"); # Create a copy so that Materials Studio can operate on it. This is required. MS will throw an exception otherwise.
	$structure->CopyFrom($source);
	$source->Discard;
	my $result;
	
	# Primary calc
	for(my $try = 1; $try <= $MaxTries; $try++)
	{
		print("Calculating " . $structure->Name . "...");
		eval { $result = CalculateStructure($structure, $module, $PrimarySettingsName, $PerformGeometryOptimization); };
		
		if($@) # Error
		{
			print("Failed try " . $try . " of " . $MaxTries . "\n");
			warn();
		}
		else # Success
		{
			print("Complete\n");
			my $resultstructure = $result->Structure;
			my $structurename = $resultstructure->Name;
			$resultstructure->ConventionalCell;
			
			$calctable->Cell($i, FindColumnIndex($calctable, "Structure")) = $resultstructure;
			$calctable->Cell($i, FindColumnIndex($calctable, "a"))         = $resultstructure->SymmetryDefinition->LengthA;
			$calctable->Cell($i, FindColumnIndex($calctable, "b"))         = $resultstructure->SymmetryDefinition->LengthB;
			$calctable->Cell($i, FindColumnIndex($calctable, "c"))         = $resultstructure->SymmetryDefinition->LengthC;
			$calctable->Cell($i, FindColumnIndex($calctable, "alpha"))     = $resultstructure->SymmetryDefinition->AngleAlpha;
			$calctable->Cell($i, FindColumnIndex($calctable, "beta"))      = $resultstructure->SymmetryDefinition->AngleBeta;
			$calctable->Cell($i, FindColumnIndex($calctable, "gamma"))     = $resultstructure->SymmetryDefinition->AngleGamma;
			$calctable->Cell($i, FindColumnIndex($calctable, "Density"))   = $resultstructure->SymmetrySystem->Density;
			$calctable->Cell($i, FindColumnIndex($calctable, "Volume"))    = $resultstructure->Lattice3D->CellVolume;
			$calctable->Cell($i, FindColumnIndex($calctable, "Symmetry"))  = $resultstructure->SymmetryDefinition->Name . " [" . $resultstructure->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
			
			if($RetrieveBandStructure eq "Yes")
			{
				my $bandfile = File::Spec->catfile($rootdir, "CalculateStructureTable_Files", "Documents", $structurename . "_BandStr.bands");
				my ($directgap, $indirectgap, $valencedispersion, $conductiondispersion, $polarity) = ParseBandStructure($bandfile);

				$calctable->Cell($i, FindColumnIndex($calctable, "Direct Band Gap")) = $directgap;
				$calctable->Cell($i, FindColumnIndex($calctable, "Indirect Band Gap")) = $indirectgap;
				$calctable->Cell($i, FindColumnIndex($calctable, "Valence Dispersion")) = $valencedispersion;
				$calctable->Cell($i, FindColumnIndex($calctable, "Conduction Dispersion")) = $conductiondispersion;
				$calctable->Cell($i, FindColumnIndex($calctable, "Polarity")) = $polarity;
			}
			
			if($RetrievePolarizability eq "Yes")
			{
				my $polarizabilityfile = File::Spec->catfile($rootdir, "CalculateStructureTable_Files", "Documents", $structurename . "_Efield.castep");
				my ($opticalpermittivity, $dcpermittivity, $opticalpolarizability, $staticpolarizability) = ParsePolarizability($polarizabilityfile);
				
				$calctable->Cell($i, FindColumnIndex($calctable, "Optical Permittivity")) = $opticalpermittivity;
				$calctable->Cell($i, FindColumnIndex($calctable, "DC Permittivity")) = $dcpermittivity;
				$calctable->Cell($i, FindColumnIndex($calctable, "Optical Polarizability")) = $opticalpolarizability;
				$calctable->Cell($i, FindColumnIndex($calctable, "Static Polarizability")) = $staticpolarizability;
			}
			$structure->Discard;
			$calctable->Save;
			last;
		}
	}
	
	# Secondary calc
	for(my $try = 1; $try <= $MaxTries && $PerformSecondaryMIBCalculation eq "Yes"; $try++)
	{
		my $primarystructure = $calctable->Cell($i, 0);
		my $mibstructure = UnpackCrystal($primarystructure, $MIBNearestNeighborDistance);
		$primarystructure->Discard;
		
		print("Calculating " . $mibstructure->Name . "...");
		eval { $result = CalculateStructure($mibstructure, $module, $SecondaryMIBSettingsName, $PerformGeometryOptimization); };
		
		if($@) # Error
		{
			print("Failed try " . $try . " of " . $MaxTries . "\n");
			$mibstructure->Discard;
			warn();
		}
		else # Success
		{
			print("Complete\n");
			my $resultstructure = $result->Structure;
			my $structurename = $resultstructure->Name;
			$resultstructure->ConventionalCell;
			
			$mibtable->Cell($i, FindColumnIndex($calctable, "Structure")) = $resultstructure;
			$mibtable->Cell($i, FindColumnIndex($calctable, "a"))         = $resultstructure->SymmetryDefinition->LengthA;
			$mibtable->Cell($i, FindColumnIndex($calctable, "b"))         = $resultstructure->SymmetryDefinition->LengthB;
			$mibtable->Cell($i, FindColumnIndex($calctable, "c"))         = $resultstructure->SymmetryDefinition->LengthC;
			$mibtable->Cell($i, FindColumnIndex($calctable, "alpha"))     = $resultstructure->SymmetryDefinition->AngleAlpha;
			$mibtable->Cell($i, FindColumnIndex($calctable, "beta"))      = $resultstructure->SymmetryDefinition->AngleBeta;
			$mibtable->Cell($i, FindColumnIndex($calctable, "gamma"))     = $resultstructure->SymmetryDefinition->AngleGamma;
			$mibtable->Cell($i, FindColumnIndex($calctable, "Density"))   = $resultstructure->SymmetrySystem->Density;
			$mibtable->Cell($i, FindColumnIndex($calctable, "Volume"))    = $resultstructure->Lattice3D->CellVolume;
			$mibtable->Cell($i, FindColumnIndex($calctable, "Symmetry"))  = $resultstructure->SymmetryDefinition->Name . " [" . $resultstructure->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
			
			if($RetrieveBandStructure eq "Yes")
			{
				my $bandfile = File::Spec->catfile($rootdir, "CalculateStructureTable_Files", "Documents", $structurename . "_BandStr.bands");
				my ($directgap, $indirectgap, $valencedispersion, $conductiondispersion, $polarity) = ParseBandStructure($bandfile);

				$mibtable->Cell($i, FindColumnIndex($calctable, "Direct Band Gap")) = $directgap;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Indirect Band Gap")) = $indirectgap;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Valence Dispersion")) = $valencedispersion;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Conduction Dispersion")) = $conductiondispersion;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Polarity")) = $polarity;
			}
			
			if($RetrievePolarizability eq "Yes")
			{
				my $polarizabilityfile = File::Spec->catfile($rootdir, "CalculateStructureTable_Files", "Documents", $structurename . "_Efield.castep");
				my ($opticalpermittivity, $dcpermittivity, $opticalpolarizability, $staticpolarizability) = ParsePolarizability($polarizabilityfile);
				
				$mibtable->Cell($i, FindColumnIndex($calctable, "Optical Permittivity")) = $opticalpermittivity;
				$mibtable->Cell($i, FindColumnIndex($calctable, "DC Permittivity")) = $dcpermittivity;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Optical Polarizability")) = $opticalpolarizability;
				$mibtable->Cell($i, FindColumnIndex($calctable, "Static Polarizability")) = $staticpolarizability;
			}
			$mibstructure->Discard;
			$mibtable->Save;
			last;
		}
	}
}

################################################################################
# CalculateStructure() - Performs calculations on a structure with the 
#                        settings applied by SetupCastepModule
sub CalculateStructure()
{
	my ($structure, $module, $settings, $optimizestructure) = @_;
	$structure->PrimitiveCell; # Perform calculation as a primitive cell
	
	$module->ResetSettings;
	$module->LoadSettings($settings);
	
	if($optimizestructure eq "Yes")
	{
		my $results = $module->GeometryOptimization->Run($structure);
		return $results;
	}
	else # Do an energy calc
	{
		my $results = $module->Energy->Run($structure);
		return $results;
	}
}

################################################################################
# Parses a .bands result file from CASTEP
# Internally, .bands uses Hartrees but this script converts to eV
# The data groups in this file are stored per-kpoint, not per-band, so some
# rearrangement into bands is necessary to compute band gaps
# Code is untested for multiple spin component systems
# Information retrieved - Direct band gap, indirect band gap
sub ParseBandStructure()
{
	my ($filename) = @_;
	
	open(my $file, "<", $filename) or die "Failed to open file: " . $filename . "\n";
	
	my $numkpoints;
	my $numelectrons;
	my $numeigenvalues;
	my $fermienergy;
	my @data2d; # 2D array in the per-kpoint order of the CASTEP .bands file
	my @valenceband; # 1D array
	my @conductionband; # 1D array
	
	my $index = 0; # index based on the current 0-based k-point in the file being processed
	
	while(<$file>)
	{
		my $line = $_;
		
		if($line =~ m/Number of k-points/)
		{
			($numkpoints) = $line =~ /(\d+)/;
		}
		elsif($line =~ m/Number of electrons/)
		{
			($numelectrons) = $line =~ /(\d+)/;
		}
		elsif($line =~ m/Number of eigenvalues/)
		{
			($numeigenvalues) = $line =~ /(\d+)/;
		}
		elsif($line =~ m/Fermi energy/)
		{
			($fermienergy) = $line =~ /([-+]?[0-9]*\.?[0-9]+)/;
			$fermienergy = $fermienergy * 27.211399; # 1.000000 Ha = 27.211399 eV
		}
		elsif($line =~ m/Spin component/) # Last line before start of numeric data
		{
			last;
		}
	}
	
	# Start parsing numeric data here
	while(<$file>)
	{
		my $line = $_;
		
		next if($line =~ m/K-point/);
		
		if($line =~ m/Spin component/) # Last line before start of next k-point data
		{
			$index++;
			next;
		}
		
		(my $energy) = $line =~ /([-+]?[0-9]*\.?[0-9]+)/;
		$energy = $energy * 27.211399; # 1.000000 Ha = 27.211399 eV
		push(@{$data2d[$index]}, $energy);
	}
	
	my $valenceindex = $numelectrons / 2 - 1;
	my $conductionindex = $numelectrons / 2;
	
	# Extract parsed numeric data in 2D array into valence and conduction bands
	foreach my $kpindex(0 .. $numkpoints - 1)
	{
		my $valenceenergy = $data2d[$kpindex][$valenceindex];
		my $conductionenergy = $data2d[$kpindex][$conductionindex];

		push @valenceband, $valenceenergy;
		push @conductionband, $conductionenergy;
	}
	
	# Extract min/maxes for the valence and conduction bands
	my $minvalence = min(@valenceband);
	my $maxvalence = max(@valenceband);
	my $minconduction = min(@conductionband);
	my $maxconduction = max(@conductionband);
	
	# Find the direct band gap
	my $directgap = 9000000;
	foreach my $kpindex(0 .. $numkpoints - 1)
	{
		if($conductionband[$kpindex] - $valenceband[$kpindex] < $directgap)
		{
			$directgap = $conductionband[$kpindex] - $valenceband[$kpindex];
		}
	}
	
	# Find the indirect band gap
	my $indirectgap = $minconduction - $maxvalence;	
	
	# Find dispersion of the valence and conduction bands
	my $valencedispersion = abs($maxvalence - $minvalence);
	my $conductiondispersion = abs($maxconduction - $minconduction);
	
	# Determine the semiconductor polarity
	my $dispersiondelta = $valencedispersion - $conductiondispersion;
	my $polarity;
	if(abs($valencedispersion - $conductiondispersion) < 0.015)
	{
		$polarity = "ambipolar";
	}
	elsif($valencedispersion - $conductiondispersion > 0.015) # Valence more disperse
	{
		$polarity = "p-type"
	}
	elsif($conductiondispersion - $valencedispersion > 0.015) # Conduction more disperse
	{
		$polarity = "n-type";
	}

	return ($directgap, $indirectgap, $valencedispersion, $conductiondispersion, $polarity);
}

################################################################################
# Parses an _Efield.castep result file for polarizability properties
# Example of data to parse:
#        Optical Permittivity (f->infinity)             DC Permittivity (f=0)
#        ----------------------------------             ---------------------
#         2.45203     0.00000     0.21387         2.68082     0.00000     0.22722
#         0.00000     2.98176     0.00000         0.00000     3.06369     0.00000
#         0.21387     0.00000     3.86665         0.22722     0.00000     3.91791
# ===============================================================================
#
# ===============================================================================
#                                    Polarisabilities (A**3)
#                Optical (f->infinity)                       Static  (f=0)
#                ---------------------                       -------------
#        39.57313     0.00000     5.82885        45.80851     0.00000     6.19260
#         0.00000    54.01031     0.00000         0.00000    56.24304     0.00000
#         5.82885     0.00000    78.12683         6.19260     0.00000    79.52382
#
sub ParsePolarizability()
{
	my ($filename) = @_;
	
	open(my $file, "<", $filename) or die "Failed to open file: " . $filename . "\n";
	
	# Property tensor scalars
	my $opticalpermittivity;
	my $dcpermittivity;
	my $opticalpolarizability;
	my $staticpolarizability;
	
	# Get Optical Permittivity and DC Permittivity tensor scalars
	while(<$file>)
	{
		my $line = $_;
		next if($line !~ m/Optical Permittivity \(f->infinity\)/ && $line !~ m/DC Permittivity \(f=0\)/); # Skip until we match these IDs
		
		$line = <$file>; # This line should be the dashed header line, skip it
		my @lineXX = split(' ', <$file>); # This line holds 6 floating point numbers (top row of two tensors)
		my @lineYY = split(' ', <$file>); # This line holds 6 floating point numbers (middle row of two tensors)
		my @lineZZ = split(' ', <$file>); # This line holds 6 floating point numbers (bottom row of two tensors)
		
		$opticalpermittivity = ($lineXX[0] + $lineYY[1] + $lineZZ[2]) / 3;
		$dcpermittivity = ($lineXX[3] + $lineYY[4] + $lineZZ[5]) / 3;
		last;
	}
	
	# Get Optical Polarizability and Static Polarizability tensor scalars
	while(<$file>)
	{
		my $line = $_;
		next if($line !~ m/Optical \(f->infinity\)/ && $line !~ m/Static  \(f=0\)/); # Skip until we match these IDs
		
		$line = <$file>; # This line should be the dashed header line, skip it
		my @lineXX = split(' ', <$file>); # This line holds 6 floating point numbers (top row of two tensors)
		my @lineYY = split(' ', <$file>); # This line holds 6 floating point numbers (middle row of two tensors)
		my @lineZZ = split(' ', <$file>); # This line holds 6 floating point numbers (bottom row of two tensors)
		
		$opticalpolarizability = ($lineXX[0] + $lineYY[1] + $lineZZ[2]) / 3;
		$staticpolarizability = ($lineXX[3] + $lineYY[4] + $lineZZ[5]) / 3;
		last;
	}
	
	return ($opticalpermittivity, $dcpermittivity, $opticalpolarizability, $staticpolarizability);
}

################################################################################
# SetupTableHeaders() - Sets up column headers for a new table
sub SetupTableHeaders()
{
	my ($table) = @_;
	
	$table->InsertColumn(0, "Structure");
	$table->InsertColumn(1, "a");
	$table->InsertColumn(2, "b");
	$table->InsertColumn(3, "c");
	$table->InsertColumn(4, "alpha");
	$table->InsertColumn(5, "beta");
	$table->InsertColumn(6, "gamma");
	$table->InsertColumn(7, "Density");
	$table->InsertColumn(8, "Volume");
	$table->InsertColumn(9, "Symmetry");
	
	my $cols = 10;
	if($RetrieveBandStructure eq "Yes")
	{
		$table->InsertColumn($cols, "Direct Band Gap");
		$table->InsertColumn($cols+1, "Indirect Band Gap");
		$table->InsertColumn($cols+2, "Valence Dispersion");
		$table->InsertColumn($cols+3, "Conduction Dispersion");
		$table->InsertColumn($cols+4, "Polarity");
		$cols = $cols + 5;
	}
	if($RetrievePolarizability eq "Yes")
	{
		$table->InsertColumn($cols, "Optical Permittivity");
		$table->InsertColumn($cols+1, "DC Permittivity");
		$table->InsertColumn($cols+2, "Optical Polarizability");
		$table->InsertColumn($cols+3, "Static Polarizability");
		$cols = $cols + 4;
	}
	
	# Delete all blank rows and columns from the table
	for(my $i = $table->RowCount - 1; $i >= 1; $i--)
	{
		$table->DeleteRow($i);
	}
	for(my $i = $table->ColumnCount - 1; $i >= $cols; $i--)
	{
		$table->DeleteColumn($i);
	}
}

################################################################################
# FindColumnIndex() - Finds a column index in a study table sheet by the header name
sub FindColumnIndex()
{
	my ($table, $headerName) = @_;
	
	for(my $col = 0; $col < $table->ColumnCount; $col++)
	{
		if($table->ColumnHeading($col) eq $headerName)
		{
			return $col;
		}
	}
	
	die "Failed to find heading " . $headerName . " within " . $table->Name;
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