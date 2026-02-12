###############################################################################
# Plot state senate district maps from dataverse shapefiles
###############################################################################

suppressMessages({
    library(sf)
    library(ggplot2)
    library(dplyr)
    library(here)
})

out_dir <- here("data-out/senate_maps")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Define state senate shapefiles
senate_files <- list(
    AK = here("dataverse_files/AK_Sen 2020/cb_2020_02_sldu_500k.shp"),
    AL = here("dataverse_files/AL_Sen 2020/tl_2025_01_sldu.shp"),
    GA = here("dataverse_files/GA_Sen 2020/tl_2020_13_sldu.shp"),
    LA = here("dataverse_files/LA_Sen 2020/tl_2020_22_sldu.shp"),
    MS = here("dataverse_files/MS_Sen 2020/tl_2020_28_sldu.shp"),
    NC = here("dataverse_files/NC_Sen 2020/tl_2020_37_sldu.shp"),
    SC = here("dataverse_files/SC_Sen 2020/cb_2020_45_sldu_500k.shp"),
    TX = here("dataverse_files/TX_Sen 2020/tl_2020_48_sldu.shp"),
    VA = here("dataverse_files/VA_Sen 2020/SCV FINAL SD.shp")
)

for (st in names(senate_files)) {
    cat("Plotting", st, "state senate districts...\n")
    shp <- st_read(senate_files[[st]], quiet = TRUE)

    # Determine the district label column
    if ("NAME" %in% names(shp)) {
        shp$district <- shp$NAME
    } else if ("NAMELSAD" %in% names(shp)) {
        shp$district <- shp$NAMELSAD
    } else if ("DISTRICT" %in% names(shp)) {
        shp$district <- shp$DISTRICT
    } else {
        # Use row number as fallback
        shp$district <- as.character(seq_len(nrow(shp)))
    }

    n_districts <- nrow(shp)

    p <- ggplot(shp) +
        geom_sf(aes(fill = district), color = "white", linewidth = 0.3) +
        scale_fill_viridis_d(option = "turbo", guide = "none") +
        labs(title = paste0(st, " State Senate Districts (n = ", n_districts, ")")) +
        theme_minimal() +
        theme(
            plot.title = element_text(hjust = 0.5, size = 16, face = "bold"),
            axis.text = element_blank(),
            axis.ticks = element_blank(),
            panel.grid = element_blank()
        )

    ggsave(file.path(out_dir, paste0(st, "_senate_districts.png")),
        plot = p, width = 10, height = 8, dpi = 150)
    cat("  Saved", st, "- ", n_districts, "districts\n")
}

cat("\nAll maps saved to", out_dir, "\n")
