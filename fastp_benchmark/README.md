[(Nucleomics-VIB)](https://github.com/Nucleomics-VIB)

Benchmark for fastq (v1.24) on paired Aviti reads
==========

## Data Availability 

Two paired nucleomics Core Aviti read files were used from a current project to evaluate the process.

4920_01_A1_20487881F4509f06A1_S5_L001_R1_001.fastq.gz (27'454'743 150b reads)
4920_01_A1_20487881F4509f06A1_S5_L001_R2_001.fastq.gz (27'454'743 150b reads)

## Method

Run fastp in increasing number of threads (1..8) and time the process. Define the optimal speedup and associated cpu costs.

## Results

<img src="pictures/fastp_times.png" alt="fastp_times" width="1000">
<img src="pictures/fastp_speedup.png" alt="fastp_speedup" width="1000">

## Conclusion

nthr=4 is optimal (3.19x faster) under the experimental setup and computing resources

<hr>

<h4>Please send comments and feedback to <a href="mailto:nucleomics.bioinformatics@vib.be">nucleomics.bioinformatics@vib.be</a></h4>

<hr>

![Creative Commons License](http://i.creativecommons.org/l/by-sa/3.0/88x31.png?raw=true)

This work is licensed under a [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/).
