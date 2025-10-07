#!/usr/bin/env Rscript

# Storage Speed Test Visualization Script
# Generates plots from storage benchmark CSV results from storage_speed_test.sh
# Usage: Rscript plot_storage_results.R <csv_file>
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
  library(scales)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  cat("Usage: Rscript plot_storage_results.R <csv_file>\n")
  cat("Example: Rscript plot_storage_results.R speed_test_results_20241007_123456.csv\n")
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

# The CSV should have format: Source,Destination,TestType,Time_s,Rate_MBps,Size_bytes
# Handle both old (7 columns with "to") and new (6 columns) formats
if (ncol(data) == 7 && names(data)[2] == "to") {
  cat("Detected old format with 'to' column - removing it...\n")
  data <- data %>% select(-to)
  names(data) <- c("Source", "Destination", "TestType", "Time_s", "Rate_MBps", "Size_bytes")
} else if (ncol(data) == 6) {
  cat("Using new CSV format (6 columns)\n")
  names(data) <- c("Source", "Destination", "TestType", "Time_s", "Rate_MBps", "Size_bytes")
}

# Convert Rate_MBps to numeric (handles "N/A" by converting to NA)
data$Rate_MBps <- as.numeric(data$Rate_MBps)

# Keep NA values but mark them for special display
# For small_file (50MB), if NA (copied in <1 sec), assume 50 MB/s minimum
data <- data %>%
  mutate(
    has_na = is.na(Rate_MBps),
    Rate_MBps = ifelse(has_na & TestType == "small_file", 100, Rate_MBps)
  )

cat("\nRows with NA values:", sum(data$has_na), "out of", nrow(data), "\n")
cat("Small file NA values replaced with 100 MB/s\n")

if (nrow(data) == 0) {
  cat("Error: No data to process!\n")
  quit(status = 1)
}

# Convert test type labels for better display
data <- data %>%
  mutate(
    TestType = case_when(
      TestType == "small_file" ~ "Small File (50MB)",
      TestType == "large_file" ~ "Large File (1GB)",
      TestType == "huge_file" ~ "Huge File (5GB)",
      TestType == "many_small_files" ~ "Many Small Files (10k×150KB)",
      TRUE ~ TestType
    ),
    TestType = factor(TestType, levels = c(
      "Small File (50MB)", 
      "Large File (1GB)", 
      "Huge File (5GB)", 
      "Many Small Files (10k×150KB)"
    ))
  )

# Define color palette
storage_colors <- c("#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b")

# ------------------------
# Plot 1: Heatmap of Transfer Rates
# ------------------------
cat("Generating heatmap...\n")

p1 <- ggplot(data, aes(x = Destination, y = Source, fill = Rate_MBps)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = ifelse(has_na, "NA", sprintf("%.1f", Rate_MBps))), 
            color = "white", size = 3, fontface = "bold") +
  facet_wrap(~ TestType, ncol = 2) +
  scale_fill_viridis(option = "plasma", name = "Rate (MB/s)", na.value = "grey80") +
  labs(
    title = "Benchmarking transfer rates between NUC5 mounts",
    subtitle = "Storage Transfer Rates Heatmap - Transfer speed (MB/s) between storage locations",
    x = "Destination Storage",
    y = "Source Storage"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 10),
    axis.text.y = element_text(size = 10),
    strip.text = element_text(size = 11, face = "bold"),
    legend.position = "right",
    panel.grid = element_blank()
  )

ggsave(file.path(output_dir, "storage_heatmap.png"), 
       plot = p1, width = 12, height = 10, dpi = 300)

# ------------------------
# Plot 2: Bar Chart - Average Rates by Test Type
# ------------------------
cat("Generating bar chart for test types...\n")

data_summary <- data %>%
  group_by(TestType) %>%
  summarise(
    Mean_Rate = mean(Rate_MBps, na.rm = TRUE),
    SD_Rate = sd(Rate_MBps, na.rm = TRUE),
    .groups = "drop"
  )

p2 <- ggplot(data_summary, aes(x = TestType, y = Mean_Rate, fill = TestType)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_errorbar(aes(ymin = Mean_Rate - SD_Rate, ymax = Mean_Rate + SD_Rate), 
                width = 0.3, linewidth = 0.7) +
  geom_text(aes(label = sprintf("%.1f MB/s", Mean_Rate)), 
            vjust = -1.5, size = 4, fontface = "bold") +
  scale_fill_manual(values = storage_colors) +
  labs(
    title = "Benchmarking transfer rates between NUC5 mounts",
    subtitle = "Average Transfer Rates by Test Type - Mean transfer speed across all storage combinations (with SD error bars)",
    x = "Test Type",
    y = "Average Rate (MB/s)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 11),
    axis.text.y = element_text(size = 11),
    legend.position = "none",
    panel.grid.major.x = element_blank()
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15)))

ggsave(file.path(output_dir, "storage_testtype_comparison.png"), 
       plot = p2, width = 10, height = 8, dpi = 300)

# ------------------------
# Plot 3: Grouped Bar Chart - Source vs Destination Performance
# ------------------------
cat("Generating source-destination comparison...\n")

# Calculate average rates for each source-destination pair
data_pairs <- data %>%
  group_by(Source, Destination) %>%
  summarise(Mean_Rate = mean(Rate_MBps, na.rm = TRUE), .groups = "drop") %>%
  mutate(Pair = paste(Source, "→", Destination))

p3 <- ggplot(data_pairs, aes(x = reorder(Pair, Mean_Rate), y = Mean_Rate, fill = Source)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = sprintf("%.1f", Mean_Rate)), 
            hjust = -0.2, size = 3.5) +
  coord_flip() +
  scale_fill_manual(values = storage_colors, name = "Source Storage") +
  labs(
    title = "Benchmarking transfer rates between NUC5 mounts",
    subtitle = "Average Transfer Rates by Storage Pair - Mean transfer speed across all test types",
    x = "Storage Transfer Pair",
    y = "Average Rate (MB/s)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    axis.text.x = element_text(size = 11),
    axis.text.y = element_text(size = 10),
    legend.position = "bottom"
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1)))

ggsave(file.path(output_dir, "storage_pairs_comparison.png"), 
       plot = p3, width = 10, height = 12, dpi = 300)

# ------------------------
# Plot 4: Box Plot - Distribution of Rates by Storage Type
# ------------------------
cat("Generating distribution box plots...\n")

data_long <- data %>%
  pivot_longer(cols = c(Source, Destination), 
               names_to = "Direction", values_to = "Storage") %>%
  select(Storage, Direction, Rate_MBps, TestType)

p4 <- ggplot(data_long, aes(x = Storage, y = Rate_MBps, fill = Direction)) +
  geom_boxplot(alpha = 0.7, outlier.shape = 16, outlier.size = 2) +
  facet_wrap(~ TestType, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("Source" = "#4daf4a", "Destination" = "#377eb8"),
                    name = "Transfer Direction") +
  labs(
    title = "Benchmarking transfer rates between NUC5 mounts",
    subtitle = "Transfer Rate Distribution by Storage Location - Box plots showing rate variability when storage acts as source or destination",
    x = "Storage Location",
    y = "Transfer Rate (MB/s)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 10),
    axis.text.y = element_text(size = 10),
    strip.text = element_text(size = 11, face = "bold"),
    legend.position = "bottom"
  )

ggsave(file.path(output_dir, "storage_distribution.png"), 
       plot = p4, width = 12, height = 10, dpi = 300)

# ------------------------
# Plot 5: Line Plot - Performance Trends Across Test Types
# ------------------------
cat("Generating performance trends...\n")

p5 <- ggplot(data, aes(x = TestType, y = Rate_MBps, 
                       group = interaction(Source, Destination), 
                       color = Source, linetype = Destination)) +
  geom_line(linewidth = 1) +
  geom_point(size = 3) +
  scale_color_manual(values = storage_colors, name = "Source") +
  scale_linetype_discrete(name = "Destination") +
  labs(
    title = "Benchmarking transfer rates between NUC5 mounts",
    subtitle = "Transfer Rate Trends Across Test Types - Performance variation for different file sizes and patterns",
    x = "Test Type",
    y = "Transfer Rate (MB/s)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 11),
    axis.text.y = element_text(size = 11),
    legend.position = "right",
    legend.box = "vertical"
  )

ggsave(file.path(output_dir, "storage_trends.png"), 
       plot = p5, width = 14, height = 8, dpi = 300)

# ------------------------
# Generate Summary Statistics
# ------------------------
cat("\n=== Summary Statistics ===\n")

# Overall performance
cat("\nOverall Performance:\n")
cat(sprintf("  Mean transfer rate: %.2f MB/s\n", mean(data$Rate_MBps, na.rm = TRUE)))
cat(sprintf("  Median transfer rate: %.2f MB/s\n", median(data$Rate_MBps, na.rm = TRUE)))
cat(sprintf("  Max transfer rate: %.2f MB/s\n", max(data$Rate_MBps, na.rm = TRUE)))
cat(sprintf("  Min transfer rate: %.2f MB/s\n", min(data$Rate_MBps, na.rm = TRUE)))

# Best and worst combinations (excluding NA values)
best <- data %>% filter(!has_na) %>% arrange(desc(Rate_MBps)) %>% slice(1)
worst <- data %>% filter(!has_na) %>% arrange(Rate_MBps) %>% slice(1)

cat("\nBest Performance:\n")
cat(sprintf("  %s → %s (%s): %.2f MB/s\n", 
            best$Source, best$Destination, best$TestType, best$Rate_MBps))

cat("\nWorst Performance:\n")
cat(sprintf("  %s → %s (%s): %.2f MB/s\n", 
            worst$Source, worst$Destination, worst$TestType, worst$Rate_MBps))

# Performance by test type
cat("\nPerformance by Test Type:\n")
test_summary <- data %>%
  group_by(TestType) %>%
  summarise(Mean = mean(Rate_MBps, na.rm = TRUE), SD = sd(Rate_MBps, na.rm = TRUE), .groups = "drop")

for (i in 1:nrow(test_summary)) {
  cat(sprintf("  %s: %.2f ± %.2f MB/s\n", 
              test_summary$TestType[i], test_summary$Mean[i], test_summary$SD[i]))
}

cat("\n✓ All plots saved to:", output_dir, "\n")
cat("\nGenerated files:\n")
cat("  - storage_heatmap.png\n")
cat("  - storage_testtype_comparison.png\n")
cat("  - storage_pairs_comparison.png\n")
cat("  - storage_distribution.png\n")
cat("  - storage_trends.png\n")
