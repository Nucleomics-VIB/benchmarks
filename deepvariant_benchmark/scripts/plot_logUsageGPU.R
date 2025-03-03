#!/usr/bin/env Rscript

# script plot_logUsageGPU.R
# description: generate a usage plot from the results of logUsageGPU.sh
# Author: SP@NC
# version 1.0
# 2025-02-05

# Check for required packages
required_packages <- c("readr", "ggplot2", "dplyr", "tidyr", "scales", "optparse", "tools")

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  stop("The following required packages are missing: ", 
       paste(missing_packages, collapse = ", "), 
       ". Please install them before running this script.")
}

# Load required libraries silently
suppressPackageStartupMessages({
  library(readr)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(scales)
  library(optparse)
  library(tools)
})

# Define command line options
option_list <- list(
  make_option(c("-i", "--input"), type="character", default=NULL, 
              help="Input file path (required)", metavar="character"),
  make_option(c("-s", "--sid"), type="character", default="Sample",
              help="Sample ID [default= %default]", metavar="character"),
  make_option(c("-o", "--output"), type="character", default=NULL,
              help="Output file path [default= input_basename.png]", metavar="character")
)

# Parse command line arguments
opt_parser <- OptionParser(option_list=option_list, usage="usage: %prog -i input_file [-s sample_id] [-o output_file]")
opt <- parse_args(opt_parser)

# Check if input file is provided
if (is.null(opt$input)) {
  print_help(opt_parser)
  stop("Input file path must be provided.", call. = FALSE)
}

# Set default output file name if not provided
if (is.null(opt$output)) {
  opt$output <- paste0(file_path_sans_ext(basename(opt$input)), ".png")
}

# Read the data
data <- read_csv(opt$input, show_col_types = FALSE)

# Calculate elapsed time in minutes
data$elapsed_time_minutes <- (data$UnixTimestamp - data$UnixTimestamp[1]) / 60

# Reshape data for plotting
data_long <- data %>%
  select(elapsed_time_minutes, `CPU_Usage(cores)`, `RAM_Usage(GB)`, `GPU_Usage(%)`, `GPU_Memory(GB)`) %>%
  pivot_longer(cols = -elapsed_time_minutes, names_to = "metric", values_to = "value")

# Create the plot
p <- suppressWarnings(
  ggplot(data_long, aes(x = elapsed_time_minutes, y = value, color = metric, linetype = metric)) +
    geom_line(linewidth = 0.75) +
    geom_point(aes(shape = metric), size = 0.75) +  # Add points
    scale_y_continuous(
      name = "CPU Usage (cores) / GPU Usage (%)",
      sec.axis = sec_axis(~ ., name = "RAM Usage (GB) / GPU Memory (GB)")
    ) +
    scale_x_continuous(
      name = "Elapsed Time (minutes)",
      breaks = seq(0, max(data$elapsed_time_minutes), by = 10),
      labels = function(x) sprintf("%.0f", x)
    ) +
    scale_color_manual(
      values = c("CPU_Usage(cores)" = "blue", "RAM_Usage(GB)" = "red", 
                 "GPU_Usage(%)" = "darkblue", "GPU_Memory(GB)" = "darkred")
    ) +
    scale_linetype_manual(
      values = c("CPU_Usage(cores)" = "solid", "RAM_Usage(GB)" = "solid", 
                 "GPU_Usage(%)" = "solid", "GPU_Memory(GB)" = "solid")
    ) +
    scale_shape_manual(
      values = c("CPU_Usage(cores)" = NA, "RAM_Usage(GB)" = NA, 
                 "GPU_Usage(%)" = 16, "GPU_Memory(GB)" = 16)
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.title.y.left = element_text(color = "blue"),
      axis.text.y.left = element_text(color = "blue"),
      axis.title.y.right = element_text(color = "red"),
      axis.text.y.right = element_text(color = "red"),
      legend.key.size = unit(1.5, "cm"),
      legend.text = element_text(size = 10),
      legend.title = element_text(size = 12, face = "bold"),
      plot.title = element_text(hjust = 0.5, face = "bold")
    ) +
    labs(
      title = paste("System Resource Usage Over Time\nSample ID:", opt$sid),
      color = "Metric",
      linetype = "Metric",
      shape = "Metric"
    ) +
    guides(
      color = guide_legend(override.aes = list(linewidth = 2, shape = c(NA, NA, 16, 16))),
      linetype = guide_legend(override.aes = list(linewidth = 2, shape = c(NA, NA, 16, 16))),
      shape = "none"
    )
)

# Save the plot
ggsave(opt$output, plot = p, width = 10, height = 6, dpi = 300)

cat("Plot saved as", opt$output, "\n")
