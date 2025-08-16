library(shiny)
library(dplyr)
library(sf)
library(plotly)
library(leaflet)
library(RColorBrewer)
library(ggplot2)
library(haven) # Added to use is.labelled

# 1. Load preprocessed data
df_sel <- readRDS("data/df_sel.Rds")
nuts3 <- readRDS("data/nuts3.Rds")

# Convert haven_labelled columns to numeric
df_sel <- df_sel %>%
  mutate(across(where(haven::is.labelled), as.numeric))

# 2. Labels for dropdowns and plot text
var_labels <- c(
  ppltrst     = "Trust in People",
  happy       = "Happiness", 
  eduyrs      = "Years of Education",
  sclact      = "Social Activity",
  polintr_rev = "Political Interest",
  health_rev  = "Self-rated Health"
)

# 3. UI definition
ui <- fluidPage(
  titlePanel("ESS 2018 Hungary: Social, Educational & Well-Being Indicators (Interactive Explorer)"),
  sidebarLayout(
    sidebarPanel(
      selectInput("var_map", "Map variable (regional average):",
                  choices = setNames(names(var_labels), var_labels),
                  selected = "ppltrst"),
      selectInput("var_scatter", "Variable to compare (individual-level):",
                  choices = setNames(names(var_labels), var_labels),
                  selected = "happy"),
      actionButton("reset_sel", "Reset Region Selection", class = "btn-warning"),
      br(), br(),
      h5("Instructions:"),
      p("• Click on map regions to explore individual data"),
      p("• Hover over points and areas for details"),
      p("• Use the plot controls (zoom, pan) to explore data")
    ),
    mainPanel(
      leafletOutput("map_plot", height = "450px"),
      verbatimTextOutput("selected_info"),
      br(),
      plotlyOutput("scatter_plot", height = "450px")
    )
  )
)

# 4. Server logic
server <- function(input, output, session) {
  # 4.1 Compute regional averages
  reg_avgs <- reactive({
    df_sel %>%
      group_by(region) %>%
      summarise(
        avg = mean(.data[[input$var_map]], na.rm = TRUE),
        n_obs = n(),
        .groups = "drop"
      )
  })
  
  # 4.2 Join to spatial data
  map_data <- reactive({
    reg_data <- reg_avgs()
    result <- nuts3 %>%
      left_join(reg_data, by = c("NUTS_NAME" = "region"))
    if(sum(!is.na(result$avg)) == 0) {
      result <- nuts3 %>%
        left_join(reg_data, by = c("NAME_LATN" = "region"))
    }
    return(result)
  })
  
  # 4.3 Track selected region
  selected_region <- reactiveVal(NULL)
  
  # 4.4 Reset selection
  observeEvent(input$reset_sel, {
    selected_region(NULL)
  })
  
  # 4.5 Display selected region info
  output$selected_info <- renderText({
    sel <- selected_region()
    if (!is.null(sel)) {
      region_data <- map_data() %>% filter(NUTS_ID == sel)
      if(nrow(region_data) > 0) {
        name <- region_data %>% pull(NAME_LATN)
        avg_val <- region_data %>% pull(avg)
        n_obs <- region_data %>% pull(n_obs)
        
        if(!is.na(avg_val)) {
          paste("Selected Region:", name, 
                "| Average", var_labels[input$var_map], ":", round(avg_val, 2),
                "| Sample size:", n_obs, "respondents")
        } else {
          paste("Selected Region:", name, "| No survey data available for this region")
        }
      } else {
        "Region data not found."
      }
    } else {
      "Click a region on the map to select it."
    }
  })
  
  # 4.6 Render interactive leaflet map
  output$map_plot <- renderLeaflet({
    sfdf <- st_transform(map_data(), 4326)
    
    vals <- sfdf$avg
    vals_clean <- vals[!is.na(vals)]
    
    if(length(vals_clean) == 0) {
      pal <- colorNumeric(palette = "YlOrBr", domain = c(0, 1), na.color = "lightgray")
    } else {
      pal <- colorNumeric(palette = "YlOrBr", domain = range(vals_clean, na.rm = TRUE), na.color = "lightgray")
    }
    
    tooltips <- paste0(
      "<b>", sfdf$NAME_LATN, "</b><br/>",
      var_labels[input$var_map], ": ", 
      ifelse(is.na(sfdf$avg), "No data", round(sfdf$avg, 2)), "<br/>",
      "Sample size: ", 
      ifelse(is.na(sfdf$n_obs), "0", sfdf$n_obs), " respondents<br/>",
      "NUTS ID: ", sfdf$NUTS_ID
    )
    
    leaflet(sfdf) %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      addPolygons(
        fillColor = ~pal(avg),
        fillOpacity = 0.7,
        color = "white",
        weight = 2,
        opacity = 1,
        highlight = highlightOptions(
          weight = 3,
          color = "#FF6600",
          fillOpacity = 0.9,
          bringToFront = TRUE
        ),
        label = ~lapply(tooltips, htmltools::HTML),
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "3px 8px"),
          textsize = "13px",
          direction = "auto"
        ),
        layerId = ~NUTS_ID
      ) %>%
      addLegend(
        pal = pal, 
        values = ~avg,
        title = paste("Average", var_labels[input$var_map]),
        opacity = 0.7,
        position = "bottomright",
        na.label = "No data"
      )
  })
  
  # 4.7 Handle map clicks
  observeEvent(input$map_plot_shape_click, {
    click <- input$map_plot_shape_click
    selected_region(click$id)
  })
  
  # 4.8 Render interactive scatterplot with hover and trend line
  output$scatter_plot <- renderPlotly({
    sel <- selected_region()
    
    if (!is.null(sel)) {
      selected_region_data <- map_data() %>% filter(NUTS_ID == sel)
      
      if(nrow(selected_region_data) > 0) {
        region_name_for_filter <- selected_region_data$NUTS_NAME[1]
        
        if(!is.na(region_name_for_filter) && !is.null(region_name_for_filter)) {
          df <- df_sel %>% filter(region == region_name_for_filter)
          region_display_name <- selected_region_data %>% pull(NAME_LATN)
          subtitle_text <- paste("Region:", region_display_name, "| N =", nrow(df), "respondents")
          scatter_title <- paste("Relationship between", var_labels[input$var_scatter], 
                                 "and", var_labels[input$var_map], "in Hungary (", region_display_name, ")")
        } else {
          df <- df_sel
          subtitle_text <- "No region-specific data available, showing all regions"
          scatter_title <- paste("Relationship between", var_labels[input$var_scatter], 
                                 "and", var_labels[input$var_map], "in Hungary")
        }
      } else {
        df <- df_sel
        subtitle_text <- "Region not found, showing all regions"
        scatter_title <- paste("Relationship between", var_labels[input$var_scatter], 
                               "and", var_labels[input$var_map], "in Hungary")
      }
    } else {
      df <- df_sel
      subtitle_text <- paste("All regions combined | N =", nrow(df), "respondents")
      scatter_title <- paste("Relationship between", var_labels[input$var_scatter], 
                             "and", var_labels[input$var_map], "in Hungary")
    }
    
    df_plot <- df %>%
      filter(!is.na(.data[[input$var_scatter]]) & !is.na(.data[[input$var_map]])) %>%
      mutate(
        hover_text = paste0(
          var_labels[input$var_scatter], ": ", round(.data[[input$var_scatter]], 2), "<br>",
          var_labels[input$var_map], ": ", round(.data[[input$var_map]], 2)
        )
      )
    
    if(nrow(df_plot) < 2) {
      p <- ggplot(df_plot) +
        geom_point(aes(x = .data[[input$var_scatter]], y = .data[[input$var_map]], text = hover_text),
                   color = "#0072B2", alpha = 0.8, size = 2) +
        labs(
          title = scatter_title,
          subtitle = subtitle_text,
          x = var_labels[input$var_scatter],
          y = var_labels[input$var_map],
          caption = "Data: ESS Round 9 (2018)"
        ) +
        theme_minimal(base_size = 12) +
        theme(
          plot.title = element_text(size = 14, face = "bold"),
          plot.subtitle = element_text(size = 12)
        )
      
      ggplotly(p, tooltip = "text") %>%
        config(displayModeBar = TRUE) %>%
        layout(hovermode = "closest", showlegend = FALSE)
    } else {
      p <- ggplot(df_plot) +
        geom_jitter(aes(x = .data[[input$var_scatter]], y = .data[[input$var_map]], text = hover_text),
                    color = "#0072B2", alpha = 0.6, width = 0.2, height = 0.2) +
        geom_smooth(aes(x = .data[[input$var_scatter]], y = .data[[input$var_map]]),
                    method = "lm", se = TRUE, color = "#D55E00") +
        labs(
          title = scatter_title,
          subtitle = subtitle_text,
          x = var_labels[input$var_scatter],
          y = var_labels[input$var_map],
          caption = "Data: ESS Round 9 (2018). Hover over points for details."
        ) +
        theme_minimal(base_size = 12) +
        theme(
          plot.title = element_text(size = 14, face = "bold"),
          plot.subtitle = element_text(size = 12)
        )
      
      ggplotly(p, tooltip = "text") %>%
        config(displayModeBar = TRUE) %>%
        layout(hovermode = "closest", showlegend = FALSE)
    }
  })
}

# 5. Run the app
shinyApp(ui = ui, server = server)
