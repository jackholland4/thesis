###############################################################################
# Combined map of all state senate districts
###############################################################################

suppressMessages({
    library(sf)
    library(ggplot2)
    library(dplyr)
    library(patchwork)
    library(here)
})

out_dir <- here("data-out/senate_maps")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

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

plots <- list()

for (st in names(senate_files)) {
    cat("Reading", st, "...\n")
    shp <- st_read(senate_files[[st]], quiet = TRUE) |>
        st_transform(4326) # common CRS for consistent rendering

    if ("NAME" %in% names(shp)) {
        shp$district <- shp$NAME
    } else if ("NAMELSAD" %in% names(shp)) {
        shp$district <- shp$NAMELSAD
    } else if ("DISTRICT" %in% names(shp)) {
        shp$district <- shp$DISTRICT
    } else {
        shp$district <- as.character(seq_len(nrow(shp)))
    }

    n_districts <- nrow(shp)

    plots[[st]] <- ggplot(shp) +
        geom_sf(aes(fill = district), color = "white", linewidth = 0.15) +
        scale_fill_viridis_d(option = "turbo", guide = "none") +
        labs(title = paste0(st, " (", n_districts, ")")) +
        coord_sf(expand = FALSE) +
        theme_void() +
        theme(
            plot.title = element_text(hjust = 0.5, size = 14, face = "bold",
                margin = margin(b = 2)),
            plot.margin = margin(5, 5, 5, 5)
        )
}

# Use layout with equal-sized cells
combined <- wrap_plots(plots, ncol = 3, heights = rep(1, 3), widths = rep(1, 3)) +
    plot_annotation(
        title = "State Senate Districts",
        theme = theme(
            plot.title = element_text(hjust = 0.5, size = 22, face = "bold",
                margin = margin(b = 10))
        )
    )

ggsave(file.path(out_dir, "all_senate_districts_combined.png"),
    plot = combined, width = 20, height = 18, dpi = 200)

cat("Combined map saved to", file.path(out_dir, "all_senate_districts_combined.png"), "\n")
