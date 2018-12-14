//gpubpm.cu
/*
 Team: Seahawks

 Program Description: Determines how many beats per minute are in a song using
 a list of frequencies that must be provided by a file in
 the command-line.

 The algorithm to determine the beats per minute were provided
 by Marco Ziccardi. His beat detection algorithm can be found in
 the link below:

 http://mziccard.me/2015/05/28/beats-detection-algorithms-1/
 */

#include <emmintrin.h>
#include <sys/time.h>
#include <stdio.h>
#include<stdlib.h>
#include<limits.h>

#define SAMPS_IN_SONG 		9281536
#define SAMPLE_RATE 		44100
#define SAMPLES_PER_MIN 	SAMPLE_RATE * 60
#define UNCALCULATED_SAMPS 	68
#define SAMPLES_PER_BLOCK 	1024
#define BLOCKS_PER_SECOND 	SAMPLE_RATE / SAMPLES_PER_BLOCK
#define C_MULTIPLIER 		-0.0000015
#define C_ADDER 			1.5142857
#define BLOCKS 43

/*Prototypes*/
int initialize(float *, int, char**);
__device__ void gpuSquared(float *, int);
__device__ void gpuCalcInstantEnergies(float *, float *);
__global__ void getInstantEnergies(float *, float *, int);
void calcBPM(float*, int);
float getAvgEnergy(float *, int);
double getVariance(float, float *, int);
double getSoil(float, float);
int calcBeats(float *, float, int);
int getBeats(float * ejs, int totalFrequencies);



int initialize(float *frequency, int argc, char** argv) {
	/*Variables*/
	FILE * file;
	file = fopen(argv[argc - 1], "r");

	int totalFrequencies = 0;
	while (fscanf(file, "%f", &frequency[totalFrequencies]) != EOF) {
		totalFrequencies++;
	}
	return totalFrequencies;
}


/*
	The GPU kernal gpuSquared(float* frequency, int totalFrequencies) accepts
	two parameters for the input vector. Each thread squares the given array's
	elements and multiplies it by two in its respective place. The size of the
	array is passed into the kernal as numOfFrequencies. The result is saved
	into the array's original position.

	The original equation provided by Marco Ziccardi takes the left and right
	frequencies at the same index, squares each of the elements and adds them
	together. However that is when the song is in stereo. This kernal only
	supports songs in mono.

	@parameters array is an array of float elements that are to be squared.
	@parameters numOfFrequencies is the number of elements in the array.
*/
__device__ void gpuSquared(float frequency[], int totalFrequencies) {
	/*Variables*/
	int element = blockIdx.x * blockDim.x + threadIdx.x;
	
	if (element < totalFrequencies)
		frequency[element] = 2 * (frequency[element] * frequency[element]);
}


/*
	Function getBlocks(float ej[], float sampleArray[], long samplesPerBlock, 
	long samples) computes the energy of a block. A block is made up of 1024
	samples in mono. The energy in a block is computed by summing a block
	of sampleArray and returning the result into the given array ej.
	The equation provided by Marco Ziccardi is:

		  1024
	Ej =   ∑  sampleArray[i]
		 i = 0

	@parameters ej is an array of floats that returns the result of the 
	summation.
	@parameters sampleArray is an array of floats that contains the results
		of each left and right frequency squared and multiplied by two
		in each index.
	@parameters samplesPerBlock indicates indicates block we are at, must
		be a multiple of 1024.
	@parameters samples is the current sample per second.
	@return ej which is an array containing the energies of the blocks.
*/
__device__ void gpuCalcInstantEnergies(float frequency[], float instantEnergy[]) {
	/*Variables*/
	unsigned int tid = threadIdx.x;
	unsigned int element = blockIdx.x * blockDim.x + tid;

	/*The last 68 samples of a second don't get computed*/
	unsigned int offset = blockIdx.x / BLOCKS_PER_SECOND;
	offset *= UNCALCULATED_SAMPS;

	instantEnergy[element] = frequency[element];
	__syncthreads();

	for (unsigned int s = 1; s < SAMPLES_PER_BLOCK; s *= 2) {
		if (tid % (2 * s) == 0) {
			instantEnergy[element + offset] += instantEnergy[element + s
					+ offset];
		}
		__syncthreads();
	}

	if (tid == 0) {
		frequency[blockIdx.x] = instantEnergy[element + offset];
	}
}

__global__ void getInstantEnergies(float * frequencies, float * energy, int samples) {
	gpuSquared(frequencies, samples);
	__syncthreads();
	
	gpuCalcInstantEnergies(frequencies, energy);
	__syncthreads();
}


/*
	Function calcBPM (float *samples, int totalFrequencies) allocates
	GPU memory and transfers the data between the CPU and GPU to get the instant
	energy of each block. Once it has the instant energies of all the elements it
	transfers the data between the GPU to the CPU and calls the following functions
	get the beat count of the song. A simple formula is then applied to this beat
	count to calculate the BPM of the song.

	@parameters samples is an array of float elements that are to be squared.
	@parameters totalFrequencies is the number of elements in the array.
*/
void calcBPM(float* samples, int totalFrequencies) {
	/*Variables*/
	int numThreads = 1024;
	int numCores = totalFrequencies / 1024 + 1;
	int bpm = 0;
	int beats = 0;

	float* gpuA;
	cudaMalloc(&gpuA, totalFrequencies * sizeof(float));
	cudaMemcpy(gpuA, samples, totalFrequencies * sizeof(float),
			cudaMemcpyHostToDevice);

	float* gpuB;
	cudaMalloc(&gpuB, totalFrequencies * sizeof(float));

	getInstantEnergies<<<numCores, numThreads>>> (gpuA, gpuB, totalFrequencies);

	cudaMemcpy(samples, gpuA, totalFrequencies * sizeof(float),
			cudaMemcpyDeviceToHost);
	cudaFree(&gpuA);
	cudaFree(&gpuB);

	/*Samples contain the instant energies*/
	beats = getBeats(samples, totalFrequencies);

	bpm = (int) ((beats * SAMPLES_PER_MIN) / totalFrequencies);
	printf("BPM = %d\n", bpm);

}


/*
	Function getAvgEnergy(float ej[]) computes the average window energy with
	a sample rate of 44100 and 43 blocks per current window, which slightly
	more than 1 second of music. The equation provided by Marco Ziccardi is:

					 42
	avg(E) = (1/43)  ∑  ej[i]
					i = 0

	@parameters ej is an array of floats containing the energy computed in 
		each block.
	@return avg is the computed average energy in the current window made
		up of 43 blocks.
 */
float getAvgEnergy(float * ejs, int currentSec) {
	/*Variables*/
	int currentEnergy = BLOCKS_PER_SECOND * currentSec;
	int lastEnergy = currentEnergy + BLOCKS_PER_SECOND;
	float avg = 0;

	while (currentEnergy < lastEnergy) {
		avg += ejs[currentEnergy];
		currentEnergy++;
	}
	avg = avg / BLOCKS;

	return avg;
}


/*
	Function getVariance(float ej[], float avg) computes the variance inside
	a window of blocks. The bigger the variance, the more likely a block will
	be considered a beat. The equation provided by Marco Ziccardi is:

					42
	var(E) = (1/43) ∑	(avg(E) - Ej)^2
				  i = 0

	@parameters ej is an array of floats containing the energy computed in
		each block.
	@parameters avg is the average energy in the current window made up of
		43 blocks.
	@return variance is the calculated variance of a window of blocks.
*/
double getVariance(float avg, float * ejs, int currentSec) {
	/*Variables*/
	float var = 0.0;
	int currentEnergy = BLOCKS_PER_SECOND * currentSec;
	int lastEnergy = currentEnergy + BLOCKS_PER_SECOND;
	float temp;

	while (currentEnergy < lastEnergy) {
		temp = avg - ejs[currentEnergy];
		var += pow(temp, 2.0);
		currentEnergy++;
	}
	var /= BLOCKS;

	return var;
}


/*
	Function getSoil(float var, float avg) computes the linear regression of the
	energy variance that lowers the impact of the variance provided by 
	Marco Ziccardi that is used to determine if a beat has occurred.
 
	C = −0.0000015 * var(E) + 1.5142857
 
	@parameters var is a float that contains the current variance.
	@parameters avg is a float that contains the average energy of the current Ej.
	@return soil returns the computed linear regression of the current energy
		variance.
 */
double getSoil(float var, float avg) {
	/*Variables*/
	float soil = 0.0;

	soil = (var * C_MULTIPLIER) + C_ADDER;
	soil *= avg;

	return soil;
}

/*
	Function calcBeats(float * ejs, float soil, int currentSec) detects
	a peak if the instant energy is bigger than c * avg(E).
	If a peak is detected 4 times in a row it is counted as a beat.

	@parameters ejs is a pointer to an array of floats that contains
		the computed ejs.
	@parameters soil contains the linear regression of the current
		energy variance.
*/
int calcBeats(float * ejs, float soil, int currentSec) {
	/*Variables*/
	int beats = 0;
	int peakCounter = 0;
	float energy = 0.0;
	int currentEnergy = currentSec * BLOCKS_PER_SECOND;
	float lastEnergy = currentEnergy + BLOCKS_PER_SECOND;

	while (currentEnergy < lastEnergy) {
		energy = ejs[currentEnergy];
		
		if (energy > soil) {
			peakCounter++;
			if (peakCounter == 4) {
				beats++;
				peakCounter = 0;
			}
		} else {
			peakCounter = 0;
		}
		currentEnergy++;
	}

	return beats;
}


/*
	Function getBeats(float * ejs, int totalFrequencies) computes per
	second the neccessary parameters to determine whether
	a beat has occured, and increments the beat count if beats are found.
 
	@parameters ejs is the array holding the instant energies
	@parameters totalFrequencies is the number of samples in the song
 */
int getBeats(float * ejs, int totalFrequencies) {
	/*Variables*/
	int beats = 0;
	int secsInSong = totalFrequencies / SAMPLE_RATE;
	float avg = 0.0;
	float var = 0.0;
	float soil = 0.0;

	int currentSec = 0;

	while (currentSec <= secsInSong) {
		avg = getAvgEnergy(ejs, currentSec);
		var = getVariance(avg, ejs, currentSec);
		soil = getSoil(var, avg);

		beats += calcBeats(ejs, soil, currentSec);
		currentSec++;
	}

	return beats;
}

int main(int argc, char** argv) {
	/*Start clock*/
	int msec = 0;
	clock_t start = clock(), diff;

	/*Variables*/
	int frequenciesInSong = 0;
	float* frequencies = (float*) malloc(INT_MAX * sizeof(float));
	printf("Starting\n");
	
	frequenciesInSong = initialize(frequencies, argc, argv);

	calcBPM(frequencies, frequenciesInSong);

	free(frequencies);

	/*Calculate Time*/
	diff = clock() - start;
	msec = diff * 1000 / CLOCKS_PER_SEC;
	printf("Time taken %d seconds %d milliseconds\n", msec / 1000, msec % 1000);

}
