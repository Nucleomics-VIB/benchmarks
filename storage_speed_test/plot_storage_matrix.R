#!/usr/bin/env Rscript

# Storage Speed Test Matrix Visualization Script
# Generates matrix layout plots: Source x Destination with test type subplots
# Usage: Rscript plot_storage_matrix.R <csv_file>
#
# SP@NC (+AI), 2025-10-07; v1.0

# Suppress default PDF device to prevent empty Rplots.pdf
pdf(NULL)

# Load required libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(viridis)
  library(gridExtra)
  library(grid)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  cat("Usage: Rscript plot_storage_matrix.R <csv_file>\n")
  cat("Example: Rscript plot_storage_matrix.R speed_test_results_20241007_123456.csv\n")
  quit(status = 1)
}

csv_file <- args[1]

# Check if file exists
if (!file.exists(csv_file)) {
  cat("Error: File", csv_file, "not found!\n")
  quit(status = 1)
}

# Create output directory
output_dir <- "pictures"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Read data
cat("Reading data from:", csv_file, "\n")
data <- read.csv(csv_file, stringsAsFactors = FALSE)

# Display column names for debugging
cat("CSV columns:", paste(names(data), collapse=", "), "\n")
cat("Number of columns:", ncol(data), "\n")

# Print raw first row to see actual data
cat("\nRaw first row:\n")
print(data[1, ])

# Check if we have the correct number of columns
if (ncol(data) == 6) {
  cat("\nCSV has 6 columns - checking if format is correct...\n")
  
  # Check if column names match expected
  expected_names <- c("Source", "Destination", "TestType", "Time_s", "Rate_MBps", "Size_bytes")
  if (all(names(data) == expected_names)) {
    cat("Column names are correct!\n")
  } else {
    cat("Column names don't match expected. Actual:", paste(names(data), collapse=", "), "\n")
    cat("Expected:", paste(expected_names, collapse=", "), "\n")
    # Force correct column names
    names(data) <- expected_names
    cat("Column names corrected.\n")
  }
} else if (ncol(data) == 7) {
  # Old format with "to" column - use column positions
  cat("Old CSV format detected (7 columns) - using column positions to skip 'to' column\n")
  data <- data[, c(1, 3, 4, 5, 6, 7)]
  names(data) <- c("Source", "Destination", "TestType", "Time_s", "Rate_MBps", "Size_bytes")
} else {
  cat("Error: Unexpected number of columns:", ncol(data), "\n")
  quit(status = 1)
}

# Print first few rows for debugging
cat("\nFirst few rows after processing:\n")
print(head(data, 10))

# Convert Rate_MBps to numeric (handles "N/A" by converting to NA)
data$Rate_MBps <- as.numeric(data$Rate_MBps)

# Keep NA values but mark them for special display
data <- data %>%
  mutate(has_na = is.na(Rate_MBps))

cat("\nRows with NA values:", sum(data$has_na), "out of", nrow(data), "\n")

# Convert test type labels for better display
data <- data %>%
  mutate(
    TestType = case_when(
      TestType == "small_file" ~ "Small File (50MB)",
      TestType == "large_file" ~ "Large File (1GB)",
      TestType == "huge_file" ~ "Huge File (5GB)",
      TestType == "many_small_files" ~ "Many Files (10K×150KB)",
      TRUE ~ TestType
    )
  )

# Define all possible test types to ensure complete data
all_test_types <- c(
  "Small File (50MB)", 
  "Large File (1GB)", 
  "Huge File (5GB)", 
  "Many Files (10K×150KB)"
)

data$TestType <- factor(data$TestType, levels = all_test_types)

# Get unique sources and destinations
sources <- sort(unique(data$Source))
destinations <- sort(unique(data$Destination))

cat("\nSources:", paste(sources, collapse=", "), "\n")
cat("Destinations:", paste(destinations, collapse=", "), "\n")
cat("Test Types:", paste(unique(data$TestType), collapse=", "), "\n")

# Define color palette
test_colors <- c(
  "Small File (50MB)" = "#1f77b4",
  "Large File (1GB)" = "#ff7f0e", 
  "Huge File (5GB)" = "#2ca02c",
  "Many Files (10K×150KB)" = "#d62728"
)

# ------------------------
# Generate Matrix Plot
# ------------------------
cat("\nGenerating matrix plot layout (Source × Destination)...\n")

# Calculate global max rate for consistent y-axis scaling
global_max_rate <- max(data$Rate_MBps[!data$has_na], na.rm = TRUE)
if (!is.finite(global_max_rate)) global_max_rate <- 100

cat(sprintf("Using global y-axis max: %.0f MB/s\n", global_max_rate))

plot_list <- list()
plot_idx <- 1

for (src in sources) {
  for (dst in destinations) {
    # Filter data for this source-destination pair
    pair_data <- data %>% 
      filter(Source == src, Destination == dst)
    
    # Complete the data with all test types (fill missing with NA)
    complete_data <- data.frame(
      Source = src,
      Destination = dst,
      TestType = factor(all_test_types, levels = all_test_types)
    )
    
    # Merge with actual data
    pair_data <- complete_data %>%
      left_join(pair_data %>% select(TestType, Rate_MBps, has_na), by = "TestType") %>%
      mutate(
        Rate_MBps = ifelse(is.na(Rate_MBps), 0, Rate_MBps),
        has_na = ifelse(is.na(has_na), TRUE, has_na)
      )
    
    # Create labels: show rate value or "NA" (using global max for positioning)
    pair_data <- pair_data %>%
      mutate(
        label_text = ifelse(has_na, "NA", sprintf("%.0f", Rate_MBps)),
        label_y = ifelse(has_na, global_max_rate * 0.05, Rate_MBps),
        label_vjust = ifelse(has_na, 0, -0.3)
      )
    
    # Create bar plot for this pair
    p <- ggplot(pair_data, aes(x = TestType, y = Rate_MBps, fill = TestType)) +
      geom_bar(stat = "identity", width = 0.7) +
      geom_text(aes(y = label_y, label = label_text, vjust = label_vjust), 
                size = 3) +
      scale_fill_manual(values = test_colors) +
      labs(
        title = paste0(src, " → ", dst),
        x = NULL,
        y = "Rate (MB/s)"
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(size = 10, face = "bold", hjust = 0.5),
        axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
        axis.text.y = element_text(size = 8),
        axis.title.y = element_text(size = 9),
        legend.position = "none",
        panel.grid.major.x = element_blank(),
        plot.margin = unit(c(0.3, 0.3, 0.3, 0.3), "cm")
      ) +
      scale_y_continuous(limits = c(0, global_max_rate * 1.15), expand = expansion(mult = c(0, 0)))
    
    plot_list[[plot_idx]] <- p
    plot_idx <- plot_idx + 1
  }
}

# Calculate grid dimensions
n_plots <- length(plot_list)
n_sources <- length(sources)
n_destinations <- length(destinations)

cat(sprintf("Creating %d plots in %d × %d grid\n", n_plots, n_sources, n_destinations))

# Create the main title
main_title <- textGrob(
  "Benchmarking transfer rates between NUC5 mounts\nSource × Destination Matrix",
  gp = gpar(fontsize = 16, fontface = "bold")
)

# Arrange plots in grid
grid_plot <- arrangeGrob(
  grobs = plot_list,
  ncol = n_destinations,
  nrow = n_sources,
  top = main_title
)

# Save the matrix plot
output_file <- file.path(output_dir, "storage_matrix.png")
ggsave(
  output_file,
  plot = grid_plot,
  width = 4 * n_destinations,
  height = 3.5 * n_sources,
  dpi = 300,
  limitsize = FALSE
)

cat("\n✓ Matrix plot saved to:", output_file, "\n")

# ------------------------
# Generate Individual Pair Plots
# ------------------------
cat("\nGenerating individual plots for each Source-Destination pair...\n")

for (src in sources) {
  for (dst in destinations) {
    pair_data <- data %>% 
      filter(Source == src, Destination == dst)
    
    if (nrow(pair_data) > 0) {
      # Create detailed plot for this pair
      p <- ggplot(pair_data, aes(x = TestType, y = Rate_MBps, fill = TestType)) +
        geom_bar(stat = "identity", width = 0.7) +
        geom_text(aes(label = sprintf("%.1f MB/s", Rate_MBps)), 
                  vjust = -0.5, size = 5, fontface = "bold") +
        scale_fill_manual(values = test_colors) +
        labs(
          title = "Benchmarking transfer rates between NUC5 mounts",
          subtitle = paste0("Transfer rates: ", src, " → ", dst),
          x = "Test Type",
          y = "Transfer Rate (MB/s)"
        ) +
        theme_minimal() +
        theme(
          plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
          plot.subtitle = element_text(size = 13, hjust = 0.5, color = "gray40"),
          axis.text.x = element_text(angle = 45, hjust = 1, size = 11),
          axis.text.y = element_text(size = 11),
          axis.title = element_text(size = 12, face = "bold"),
          legend.position = "none",
          panel.grid.major.x = element_blank()
        ) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.15)))
      
      # Save individual plot
      filename <- paste0("storage_", src, "_to_", dst, ".png")
      ggsave(
        file.path(output_dir, filename),
        plot = p,
        width = 10,
        height = 7,
        dpi = 300
      )
      
      cat(sprintf("  - Saved: %s\n", filename))
    }
  }
}

# ------------------------
# Generate Summary Statistics
# ------------------------
cat("\n=== Summary Statistics ===\n")

# Performance by pair
cat("\nPerformance by Source-Destination Pair:\n")
pair_summary <- data %>%
  group_by(Source, Destination) %>%
  summarise(
    Mean_Rate = mean(Rate_MBps),
    Max_Rate = max(Rate_MBps),
    Min_Rate = min(Rate_MBps),
    .groups = "drop"
  ) %>%
  arrange(desc(Mean_Rate))

for (i in 1:nrow(pair_summary)) {
  cat(sprintf("  %s → %s: Avg %.1f MB/s (Max: %.1f, Min: %.1f)\n",
              pair_summary$Source[i],
              pair_summary$Destination[i],
              pair_summary$Mean_Rate[i],
              pair_summary$Max_Rate[i],
              pair_summary$Min_Rate[i]))
}

# Performance by test type
cat("\nPerformance by Test Type:\n")
test_summary <- data %>%
  group_by(TestType) %>%
  summarise(
    Mean_Rate = mean(Rate_MBps),
    SD_Rate = sd(Rate_MBps),
    .groups = "drop"
  )

for (i in 1:nrow(test_summary)) {
  cat(sprintf("  %s: %.1f ± %.1f MB/s\n",
              test_summary$TestType[i],
              test_summary$Mean_Rate[i],
              test_summary$SD_Rate[i]))
}

cat("\n✓ All plots completed!\n")
