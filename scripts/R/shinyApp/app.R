#ASTROYEAST MULTISTRESS WEBAPP
#Author: Benjamin Clark 



#License

# © Copyright 2020 iGEM Concordia, Maher Hassanain, Benjamin Clark, Hajar Mouddene, Grecia Orlano
# This file is part of AstroBio.
# AstroBio is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or any later version.
# AstroBio is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with AstroBio.  If not, see <https://www.gnu.org/licenses/>.


library(shiny)
library(Biobase)
library(dplyr)
library(sjmisc)
library(ComplexHeatmap)
source("custom_draw.R")
suppressPackageStartupMessages(library(factoextra))
source("metastudy_functions.R")
load("data/appdata.RData")
source("volcano_builder.R")


#__________Error handling__________
is.empty <- function(var){
  return(var == "" || var == 0)
}

name.check <- function(models, names){
  model <- switch(models, 
                  "HeatShock" = rem_g5.v.he7@metaresult,
                  "Oxidative Stress" = rem_g5.v.ox6@metaresult,
                  "High Osmolarity" = rem_g5.v.osm6@metaresult ,
                  "All of the Above"= all_rem@metaresult)
  return(all(names %in% model$Symbol))
}

validate_id <- function(gene_names, models){
  if(!all(sapply(models, FUN = name.check,  names = gene_names))){
    showNotification("Invalid Gene Name", type = "error")
    return("Invalid Gene Names")
  }
  else if(gene_names == ""){
  return(FALSE)
  }
  else{
    return(NULL)
  }
  
}
numeric_or_empty <- function(var){
  return(!is.na(as.numeric(var) || var == ""))
}
query.validate <- function(input){
  if(all(sapply(input, FUN = is.empty))){
    return(FALSE)
  }
  else if(suppressWarnings(!all(sapply(input, FUN = numeric_or_empty)))){
    return("Invalid inputs, please provide an integer")
  }
  else{
    return(NULL)
  }
}


forest_validate <- function(name, model){
  if(name == "" || name == "Enter Common Gene Name"){
    return(FALSE)
  }
  else if(!(name %in% model$Symbol)){
    return("Invalid Gene Name")
  }
  else{
    return(NULL)
  }
}

tab_validate <- function(tab_input){
  if(tab_input == "About"){
    return(FALSE)
  }
  else{
    return(NULL)
  }
}

#____________Query Functions___________
#helper functions for querying
at_least <- function(num_vector, q_val){
  #print(q_val)
  if(q_val == ""){
    return(NULL)
  }
  if(q_val < 0){
    return(num_vector <= q_val)
  }
  else if(q_val > 0){
    return(num_vector >= q_val)
  }
  
  else{
    return(NULL)
  }
}

#handling duplicate spots
median_dups <- function(logfc2, dupList){
  medians <- list()
  for(i in 1:length(dupList)){
    fc <- median(logfc2[as.vector(dupList[[i]])])
    medians[names(dupList)[i]] <- list(fc)
  }
  return(medians)
}
make_dup_list <- function(vnames){
  out <- list()
  i <- 1
  q_list <- vnames
  while(length(q_list > 1)){
    
    query <- vnames[i]
    
    q <- which(vnames == query)
    out[query] <- list(q)
    
    i <- i + 1
    
    q_list <- q_list[q]
    
  }
  #removing singles
  out <- out[which(as.vector(sapply(out, "length")) >= 2)]
  
  return(out)
  
}

put_na <- function(bool_set){
  if(bool_set){
    return(0)
  }
  else{
    return(NA)
  }
}

#requires a model to be loaded in the namespace and a list of gene names derived from query
pull_queried <- function(gene_ids, smodel){
  
  
  model <- switch(smodel, 
                  "HeatShock" = grav5.vs.he7,
                  "Oxidative Stress" = grav5.vs.ox6,
                  "High Osmolarity" = grav5.vs.osm6,
                  "All of the Above"= diff_all_f)
  
  whole_set <- list()
  for(i in 1:length(model)){
    #picking apart valid and invalid ids
    valid_ids <- which(gene_ids %in% model[[i]]$Symbol)
    
    nvalid_ids <- which(!(gene_ids %in% model[[i]]$Symbol))
    
    bool_set <- gene_ids %in% model[[i]]$Symbol
    #adding NAs to unavailable ids
    log2fc <- sapply(bool_set, FUN = put_na)
    
    #dealing with duplicate entries by taking the median from the database
    whole_ids <- model[[i]]$Symbol[model[[i]]$Symbol %in% gene_ids]
    
    dups <- make_dup_list(whole_ids)
    
    if(length(dups) > 0){
      med_dups <- median_dups(logfc2 = model[[i]]$Log2FC, dupList = dups)
    
      #the duplicate location within the input id list
      dup_loc <- which(gene_ids %in% names(dups))
    
      log2fc[dup_loc] <- unlist(unname(med_dups))
    
      #removing valid_ids which are duplicates
      valid_ids <- valid_ids[which(!( valid_ids %in% dup_loc))]}
    
    
    log2fc[valid_ids] <-  model[[i]]$Log2FC[which(model[[i]]$Symbol %in% gene_ids[valid_ids])]
    names(log2fc) <- gene_ids
    
    #print(names(model))
    whole_set[names(model)[[i]]] <- list(log2fc)
    
    
    
  }
  #browser()
  dfs <- lapply(whole_set, data.frame, stringsAsFactors = FALSE)
  binded.ids <- bind_cols(dfs)
  #rownames(binded.ids) <- gene_ids
  colnames(binded.ids) <- names(model)
  return(binded.ids)
  
}

#Expects a list with named variables matching the ui tags
query <- function(varlist, smodel){

  
  out.ids <- list()
  #print(varlist)
  #print(smodel)
  model <- switch(smodel, 
                 "HeatShock" = rem_g5.v.he7@metaresult,
                 "Oxidative Stress" = rem_g5.v.ox6@metaresult,
                 "High Osmolarity" = rem_g5.v.osm6@metaresult ,
                 "All of the Above"= all_rem@metaresult)
  
  
  
  for(i in 1:length(varlist)){
    #getting the intersection of queries from the REM dataset
        
      name <- names(varlist)[i]
      #print(name)
      #print(varlist[[i]])
      if(varlist[[i]] != ""){
        out.var <- switch(name,
                          "logfc2" = at_least(model["randomSummary"], q_val = as.numeric(varlist[[i]])),
                          "tRank" = model["rank"] <= as.numeric(varlist[[i]]),
                          "signcon" = model["signcon"] == as.numeric(varlist[[i]]),
                          "all" = c(rep(TRUE, length(model$Symbol)))
                          )
      
      
      out.ids[name] <- list(out.var)
      }
    }
    
     
      
    
    
  
  dfs <- lapply(out.ids, data.frame, stringsAsFactors = FALSE)
  binded.ids <- bind_cols(dfs)
  rownames(binded.ids) <- model$Symbol
  #print(head(binded.ids))
  return(row.check(binded.ids))
}

row.check <- function(df){
  #rotate my data.frame bb
  df <- t(df)
  #output
  out <- c()
  #iterate and find the rows that are all true
  for(col in 1:length(df[1,])){
    if(all(df[,col])){
      out <- append(out, colnames(df)[col]) 
    }
  }
  return(out)
  
}



#  UI for application 
ui <- fluidPage(
   
   # Application title
   titlePanel("AstroBio MultiStress Explorer"),
   
   # Sidebar 
   sidebarLayout(
      sidebarPanel(
        
         selectInput("var",
                     label = ("Choose a Metastudy"),
                     choices = c("HeatShock",
                                 "Oxidative Stress",
                                 "High Osmolarity",
                                 "All of the Above"),
                     selected = "Heatshock"),
        
         textInput("gene", label = "Gene Forest Plot", 
                   value = "HSP30"),
         helpText("Choose threshold values to display on a pca biplot "),              
         fluidRow(
  
           column(3,
                 textInput('logfc2', label = "Summary Log2-Fold Change")),
           
         
           column(3,
                 textInput('tRank', 'Number of Top Ranking Genes')),
           
           
           column(3, textInput("signcon", label = "Sign Consistency"))
           
         
          ),
         helpText("Enter common gene names from S.cerevisiae genome. Multiple entries can be entered using ',' 
                  as a delimiter with no spaces between and in all caps. Ex : ADR1,UPC2" ),
         textInput("id", label = "Plot Specific Gene Values"),
         actionButton("save", label = "Show IDs on PCA-Biplot"),
         actionButton("reset_pca", "Reset PCA-Biplot"),
         helpText("Number of Queried Genes:"),
         verbatimTextOutput("table_summary"),
         downloadButton("download", label = "Download PCA-Biplot Data")
         
      ),
        

      
      
      mainPanel(
        
        tabsetPanel(type = "tabs", id = "panel",
          tabPanel("About", includeHTML("about.html")),
          tabPanel("Graphs", 
            plotOutput("volcano", hover = "plot_hover", click = "plot_click"),
            # fluidRow(column(3, textOutput("vname")),
            #          column(3, textOutput("vfc")),
            #          column(3, textOutput("vsign")),
            #          column(3, textOutput("vpval"))),
            verbatimTextOutput(outputId = "text_hover"),
            plotOutput("forest"),
            plotOutput("pca"),
            plotOutput("heat")
            )
          
        )
          
          
      )
    )
        
)



initial_txt <- function(string){
  return(string == "Enter Common Gene Name" || string == "")
}

server <- function(input, output) {

  
#______________Reactive Functions___________________
  reactive_rem <- reactive({
    switch(
      input$var,
      "HeatShock" = rem_g5.v.he7@metaresult,
      "Oxidative Stress" = rem_g5.v.ox6@metaresult,
      "High Osmolarity" = rem_g5.v.osm6@metaresult,
      "All of the Above" = all_rem@metaresult
    )
  }) 

 
  #query function based off of predefined parameters 

# Same as reactive_query but pulls info from the respective random effects models
  reactive_pull_query <- reactive({
    validate(query.validate(
      list(
        logfc2 = input$logfc2,
        tRank = input$tRank,
        signcon = input$signcon
      )
    ))
    pull_queried(query(
      varlist = list(
        logfc2 = input$logfc2,
        tRank = input$tRank,
        signcon = input$signcon
      ),
      smodel = input$var
    ), smodel = input$var)
  })

  
# Pulls valid gene ids based off of input queries. Will notify if non-numeric is entered. Will fail silently when only 0 is entered.  
  reactive_query <- reactive({
    #Validate the inputs 
    validate(query.validate(
      list(
        logfc2 = input$logfc2,
        tRank = input$tRank,
        signcon = input$signcon
      )
    ))
    #make sure the right page is open 
    if (input$panel == "About") {
      showNotification("Navigate to the Graphs tab to view results.", type = "message")
      
    }
    #main query function
    query(
      varlist = list(
        logfc2 = input$logfc2,
        tRank = input$tRank,
        signcon = input$signcon
      ),
      smodel = input$var
    )
  })
  
  
   
  
#____________Rendering Volcano Plot____________________
   output$volcano <- renderPlot({
            showNotification("Loading Plots...")
            #Sys.sleep(15)
            showNotification("Click on points on the volcano plot to see how gene 
                    expression changes or type the gene name in the 'Gene Forest Plot' window.", 
                             type = "message", duration = 40)
            switch(input$var, 
            "HeatShock" = build_volcano(rem_g5.v.he7@metaresult),
            "Oxidative Stress" = build_volcano(rem_g5.v.ox6@metaresult),
            "High Osmolarity" = build_volcano(rem_g5.v.osm6@metaresult),
            "All of the Above"= build_volcano(all_rem@metaresult))
     
            
     })
   
   
#_____________On Hover Info________________
   output$text_hover <- renderPrint({
     nearPoints(
       df = build_volcano(reactive_rem())$data,
       threshold = 10,
       maxpoints = 5,
       coordinfo = input$plot_hover
     ) %>%
       dplyr::rename(
         Summary_Pval = randomP,
         Summary_LogFC = randomSummary,
         Sign_Consistency = signcon
       ) %>% 
        dplyr::mutate(
           Summary_Pval = 10^-(Summary_Pval)
        )
     
   })
   
#____________Rendering Forest Plot__________
   output$forest <- renderPlot({
     if (!is.null(input$plot_click) &&
         !plyr::empty(
           nearPoints(
             df = build_volcano(reactive_rem())$data,
             threshold = 10,
             maxpoints = 1,
             coordinfo = input$plot_click
           )
         )) {
       reactive_data$forest_name <-
         nearPoints(
           df = build_volcano(reactive_rem())$data,
           threshold = 10,
           maxpoints = 1,
           coordinfo = input$plot_click
         )$Symbol
       
     }
     else{
       validate(forest_validate(name = input$gene, model = reactive_rem()))
       reactive_data$forest_name <- input$gene
     }
     meta_degs_rem <- switch(
       input$var,
       "HeatShock" = rem_g5.v.he7,
       "Oxidative Stress" = rem_g5.v.ox6,
       "High Osmolarity" = rem_g5.v.osm6,
       "All of the Above" = all_rem
     )
     
     
     
     draw_forest2(remres = meta_degs_rem,
                  gene = reactive_data$forest_name,
                  draw = "")
     
   })
   

   
   
   

   
   output$table_summary <- renderText({
     
     reactive_data$q_length <- length(reactive_query())
     reactive_data$q_length})
   
   
   #reactive dataset
   reactive_data <- reactiveValues(
     pca = NULL,
     labels = c(),
     specific_labels = NULL,
     q_length = 0,
     show_label = c("all"),
     row_label = FALSE,
     forest_name = NULL
   )
   
   build_pca_data <- reactive({prcomp((na.omit(pull_queried(query(varlist = list(all = TRUE), smodel = input$var), smodel = input$var))))})
   
   #When save ids is clicked, save them in session
   observeEvent(input$save, {
     if (input$id != "") {
       validate(validate_id(
         gene_names = strsplit(input$id, split = ",")[[1]],
         models = input$var
       ))
       
       reactive_data$labels <- strsplit(input$id, split = ",")[[1]]
       #print(!sapply(c(logfc2 = input$logfc2, tRank = input$tRank, signcon = input$signcon), FUN = is.empty))
     }
     
     
     
     else if (any(!sapply(
       c(
         logfc2 = input$logfc2,
         tRank = input$tRank,
         signcon = input$signcon
       ),
       FUN = is.empty
     ))) {
       #print(TRUE)
       reactive_data$labels <- rownames(reactive_pull_query())
     }
     
     
     if (reactive_data$q_length > 60) {
       reactive_data$show_label <- c("var")
     }
     
     else{
       reactive_data$show_label <- "all"
     }
     
     #print(reactive_data$labels)
     output$pca <-
       renderPlot({
         factoextra::fviz_pca_biplot(
           build_pca_data(),
           label = reactive_data$show_label,
           select.ind = list(name = reactive_data$labels),
           col.var = "contrib",
           ggtheme = theme_classic(),
           repel = TRUE, gradient.cols = c(low = "cyan1", high = "blue")
         )
         
       })
     
   })
   #resetting the biplot
   observeEvent(input$reset_pca, {
     output$pca <-
       renderPlot({
         factoextra::fviz_pca_biplot(
           build_pca_data(),
           label = "var",
           col.var = "contrib",
           ggtheme = theme_classic(),
           repel = TRUE, gradient.cols = c(low = "cyan1", high = "blue")
         )
       })
   })
   
  
   output$heat <- renderPlot({
     validate(query.validate(input = c(
       input$logfc2, input$tRank, input$signcon
     )))#,
     #tab_validate(tab_input = input$panels))
     
     
     
     if (reactive_data$q_length < 100) {
       reactive_data$row_label <- TRUE
     }
     else{
       reactive_data$row_label <- FALSE
     }
     
     if (reactive_data$q_length > 0) {
       Heatmap(
         as.matrix(na.omit(
           pull_queried(reactive_query(), smodel = input$var)
         )),
         heatmap_legend_param = list(title = "Log2FC"),
         show_row_names = reactive_data$row_label
       )
     }
   })
      
  


   output$pca <- renderPlot({factoextra::fviz_pca_biplot(build_pca_data(), label = "var", col.var = "contrib", ggtheme = theme_classic(), gradient.cols = c(low = "cyan1", high = "blue"))})
   output$download <- downloadHandler(filename = "AstroYeast_logfcs.csv", 
                                      content = function(file){
                                        write.csv(pull_queried(query(varlist = list(all = TRUE), smodel = input$var), smodel = input$var), file = file)
                                      })
}

# Run the application 
shinyApp(ui = ui, server = server)

