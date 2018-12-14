#include <emmintrin.h>
#include <sys/time.h>
#include <stdio.h>
#include <time.h>
#include<stdlib.h>
#include<limits.h>

#define SAMPLES_PER_SECOND 44100
#define SAMPLES_PER_BLOCK 1024
#define BLOCKS 43

/*Global Array*/
float sampleArray[INT_MAX];

/*
	Function calculateSample(float sampleArray[], long samples) iterates
	throught the sample array of frequencies and squares each element by itself
	and multiples it by 2. The result is stored back into the current array 
	index.
	
	@parameters sampleArray is an array of float elements that are to be squared.
	@parameters samples is the number of elements in the array.
	@return sampleArray returns the computed sample array/.
*/
float * calculateSample(float sampleArray[], long samples){
	/*Variables*/
	long i = samples - SAMPLES_PER_SECOND;
	
	for(; i < samples; i++){
		sampleArray[i] = (sampleArray[i] * sampleArray[i]) * 2;
	}
	
	return sampleArray;
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
float * getBlocks(float ej[], float sampleArray[], long samplesPerBlock, long samples){
	/*Variables*/
	long i = samples - SAMPLES_PER_SECOND;
	long j = 0;
	float sum = 0.0;

	for(j = 0; j < BLOCKS; j++){
		for(; i < samplesPerBlock; i++){
			sum += sampleArray[i];
		}
		samplesPerBlock += SAMPLES_PER_BLOCK;
		ej[j] = sum;
		sum = 0;
	}
	return ej;
}
/*
	Function getAvg(float ej[]) computes the average window energy with
	a sample rate of 44100 and 43 blocks per current window, which slightly
	more than 1 second of music. The equation provided by Marco Ziccardi is:

					 42
	avg(E) = (1/43)  ∑  ej[i]
					i = 0

	@parameters ej is an array of floats containing the energy computed in 
		each block.
	@return avg is the computed average energy in the current window made
		up of 43 blocks

*/
float getAvg(float ej[]){
	/*Variables*/
	long i = 0;
	float avg = 0.0;
	
	for(i = 0; i < BLOCKS; i++){
		avg += ej[i];
	}
	avg = avg/BLOCKS;
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
float getVariance(float ej[], float avg){
	/*Variables*/
	long i = 0;
	float variance = 0.0;
	
	for(i = 0; i < BLOCKS; i++){
		variance += ((avg - ej[i]) * (avg - ej[i])) / BLOCKS;
	}
	return variance;
}

int main(int argc, char** argv){
	/*Start clock*/
	int msec = 0;
	clock_t start = clock(), diff;
	printf("Starting\n");
	
	/*Variables*/
	FILE * file;
	float ej[BLOCKS];
	long i = 0;
	long j = 0;
	long samples = SAMPLES_PER_SECOND;
	long samplesPerBlock = SAMPLES_PER_BLOCK;
	float avg = 0.0;
	float variance = 0.0;
	float c = 0.0;
	long beats = 0;
	long peak = 0;
	int bpm = 0.0;
	long totalSamples = 0;
	
	file = fopen(argv[argc - 1], "r");
	
	while(fscanf(file, "%f", &sampleArray[i]) != EOF){
		totalSamples++;
		i++;
	}
	
	for(i = 0; i < totalSamples; i++){
		
		if(i == samples - 1){
			calculateSample(sampleArray, samples);
			
			getBlocks(ej, sampleArray, samplesPerBlock, samples);
			
			avg = getAvg(ej);
			
			variance = getVariance(ej, avg);
			
			c = -0.0000015 * variance + 1.5142857;
			
			
			for(j = 0; j < BLOCKS; j++){
				if(ej[j] > (c * avg)){
					
					peak++;
					if(peak == 4){
						beats++;
						peak = 0;
					}
				}
				else{
					peak = 0;
				}
			}
			
			samples += SAMPLES_PER_SECOND;
			samplesPerBlock += SAMPLES_PER_SECOND;
		}
	}
	bpm = (int)(beats * SAMPLES_PER_SECOND * 60) /totalSamples;
	printf("BPM = %d\n", bpm);
	
	/*Calculate Time*/
	diff = clock() - start;
	msec = diff * 1000 / CLOCKS_PER_SEC;
	printf("Time taken %d seconds %d milliseconds\n", msec / 1000, msec % 1000);
	
	return 0;
}