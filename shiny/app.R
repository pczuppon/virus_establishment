#
# This is a Shiny web application. 
#
# If you have downloaded the file, you can run the application by 
# -  opening it with RStudio, and 
# -  clicking the 'Run App' button above.
#
# To download RStudio: https://rstudio.com/products/rstudio/download/ (choose "free")
#

# To deploy
# install.packages('rsconnect')
# library(rsconnect)
# deployApp()


library(shiny)
library(deSolve)

# Define UI for application that draws a histogram
ui <- fluidPage(
  
  # Application title
  titlePanel("Within-host model"),
  h1("Model"), 
  p("We follow the dynamics of populations of infected cells in eclipse phase (\\(I_1\\)),
      infected cells that produce virions (\\(I_2\\)),
      infectious virions (\\(V_I\\)),
      non-infectious / inactive virions (\\(V_{NI}\\)),
      and finally target cells (\\(T\\))."),
  p("The system of ODEs is the following: 
    $$\\begin{align} 
       \\frac{d I_1}{dt} &= (1-\\epsilon_{\\beta})\\beta \\, T(t) \\, V_I(t) - k \\, I_1(t), \\\\
       \\frac{d I_2}{dt} &= k \\, I_1(t) - \\delta \\, I_2(t), \\\\
       \\frac{d V_I}{dt} &= \\mu (1-\\epsilon_{B}) p \\, I_2(t) - c \\, V_I(t) - (1-\\epsilon_{\\beta})\\beta \\, T(t) \\, V_I(t), \\\\
       \\frac{d V_{NI}}{dt} &= (1-\\mu) (1-\\epsilon_{B}) p \\, I_2(t) - c \\, V_I(t), \\\\
       \\frac{d T}{dt} &= - (1-\\epsilon_{\\beta})\\beta \\, T(t) \\, V_I(t). \\end{align}$$"),
  
  p('The probability of establishment is 
    $$\\begin{align}
    \\phi &= 0 \\textsf{ if } R_0 <1,\\\\
    \\phi &= 1 - \\left( 1 - \\frac{R_0 - 1}{\\mu B}\\right)^{V_0} \\textsf{ otherwise.}
    \\end{align}$$'),
  br(),
  p(  '-  A drug that affects virus production \\(p\\) by a factor \\((1 - \\epsilon_p)\\) affects both \\(B\\) and \\(R_0\\) by a factor \\((1 - \\epsilon_p)\\). ', br(), 
      '-  A drug that affects infectivity \\(\\beta\\) by a factor \\((1 - \\epsilon_{\\beta})\\) changes only \\(R_0\\), by a factor \\((1 - e(\\epsilon_{\\beta})) = 1 - \\frac{c \\epsilon_{\\beta}}{c + (1 - \\epsilon_{\\beta}) \\beta T_0}\\).
                         '),
  h4("Parameters affecting both figures"),
  div(class = "shiny-input-panel",
      fluidRow(
        # Input values
        column(3, 
               sliderInput(inputId = "R0", 
                           label = "R0", 
                           min = 2, 
                           max = 20, 
                           value = 7.69, 
                           step = 0.2)
        ),
        column(3,
               sliderInput(inputId = "B", 
                           label = "Burst size (N)", 
                           min = 1880, 
                           max = 188000, 
                           value = 18800, 
                           step = 10)
        ),
        column(3,
               sliderInput(inputId = "V0", 
                           label = "Initial number of infectious virions (\\(V_{0}\\))", 
                           min = 1, 
                           max = 50, 
                           value = 10, 
                           step = 1)),
        column(3,
               sliderInput(inputId = "mu", 
                           label = "Proportion of infectious virions (\\(\\mu\\))", 
                           min = 0, 
                           max = 0.1, 
                           value = 0.001, 
                           step = 0.0001)),
      ), 
      fluidRow(
        column(3, 
               sliderInput(inputId = "c", 
                           label = "Rate of virus clearance (\\( c\\))", 
                           min = 1, 
                           max = 20, 
                           value = 10, 
                           step = 0.5)
        ),
        #
        column(3, 
               numericInput(inputId = "T0", label = 'Initial amount of target cells (\\(T_0\\))', value = 1330)
        ),
        #
        column(3, 
               withMathJax(textOutput(outputId = "betaValue")))
      )
  ),
  h4("Parameters affecting within-host dynamics only"),
  div(class = "shiny-input-panel",
      fluidRow(
        column(3, 
               sliderInput(inputId = "k", 
                           label = "Rate of transition out of eclipse phase (\\(k\\))", 
                           min = 1, 
                           max = 10, 
                           value = 5, 
                           step = 0.1)
        ),
        column(3,
               #
               sliderInput(inputId = "delt", 
                           label = "Rate of infected cell death (\\( \\delta\\))", 
                           min = 0.1, 
                           max = 1, 
                           value = 0.595, 
                           step = 0.02)
        ),
        column(3,
               withMathJax(textOutput(outputId = "pValue"))),
      ),
      fluidRow(
        #
        #
        column(3,
               withMathJax(),
               sliderInput(inputId = "epsbeta",
                           label = "Efficacy of drug reducing virus infectivity \\(\\beta\\) (\\( \\epsilon_{\\beta}\\))", 
                           min = 0, 
                           max = 0.99, 
                           value = 0, 
                           step = 0.01)
        ),
        #
        column(3,
               withMathJax(),
               sliderInput(inputId = "epsp",
                           label = "Efficacy of drug reducing virus production \\(p\\) (\\( \\epsilon_{B}\\))", 
                           min = 0, 
                           max = 0.99, 
                           value = 0, 
                           step = 0.01)
        )
      )
  )
  ,
  fluidRow(
    column(6, plotOutput("ODEplot"))
    ,
    column(6,  
           # Output: Plot ----
           plotOutput(outputId = "EstablishmentProbaPlot")
    )),
  p()
)

#
#===================================================================================
#

server <- function(input, output) {
  # Establishement probability -------------------------
  
  # Establishment probability when the drug affects burst size
  phi.B <- function(x, parms){
    with(as.list(parms), {
      BB <- (1-x)*B;
      RR0 <- (1-x)*R0
      if(RR0 < 1){
        out <- 0.0
      }else{
        out <- 1 - (1 - (RR0-1)/(mu * BB))^V0
      }
      return(out)
    })
  }
  
  # Establishment probability when the drug affects transmission
  phi.beta <- function(x, parms){
    with(as.list(parms), {
      RR0 <- R0 * (1 - (c * x)/(c + (1-x)* bet * T0))
      if(RR0 < 1){
        out <- 0.0
      }else{
        out <- 1 - (1 - (RR0-1)/(mu * B))^V0
      }
      return(out)
    })
  }
  
  npts <- 101
  # Define values of epsilon to be tested
  epsVals <- seq(0, 1, length.out = npts)
  # Initialize output vector
  y.B <- y.beta <- rep(NA, npts)
  
  # Plot colors
  colB <- "#2077b4" # Blue
  colbet <- "#ff7f0e" # Orange
  thelwd <- 2
  
  
  # Plot
  output$EstablishmentProbaPlot <- renderPlot({
    # Initial conditions
    state <- c(eclipseCells = 0,
               infectedCells = 0,
               virions = input$V0, 
               targetCells = input$T0)
    
    # Model parameters
    tmp <- c(k = input$k, 
             delt = input$delt, 
             c = input$c, 
             p = input$B * input$delt, 
             mu = input$mu,
             R0 = input$R0, 
             epsp = input$epsp, 
             epsbeta = input$epsbeta, 
             B = input$B, 
             V0 = input$V0, 
             T0 = input$T0)
    # Compute beta out of the parameters
    bet <- with(as.list(c(tmp, state)), R0 * c / ((mu*p/delt - R0) *targetCells))
    # All parms
    parms <- c(tmp, bet = bet)
    
    
    for(i in 1:npts){
      y.B[i] <- phi.B(epsVals[i], parms)
      y.beta[i] <- phi.beta(epsVals[i], parms)
    }
    
    par(las = 1)
    par(mar = c(4, 6, 5, 6))
    
    plot(epsVals, y.B, ylim = c(0, 1), type = "l", col = colB, lwd = thelwd,
         xlab = expression(paste("Antiviral drug efficiency ", epsilon)),
         ylab = expression(paste("Establishment probability ", phi)), 
         main = "Establishment Probability \n Continuous production model")
    lines(epsVals, y.beta, col = colbet, lwd = thelwd)
    
    # Legend
    legend(0, 0, legend = c("reducing burst size B", expression(paste("reducing infectivity ", beta))), yjust = 0, lty = c(1, 1), col = c(colB, colbet), lwd = thelwd, bty = "n")
    
  })
  #
  #------------------------------------------------
  # COMBINATION PLOT
  output$CombinationPlot <- renderPlot({
    par(pty="s")
    par(las = 1)
    xx <- seq(0, 0.99, by = 0.01)
    plot(xx, 1 + input$B / (input$R0 - input$B * (1 - xx) * input$R0), 
         type = "l",
         xlim = c(0, 1), ylim = c(0, 1), 
         asp = 1, 
         xlab = expression(epsilon[B]), 
         ylab = expression(epsilon[beta]), 
         col = "orange", lwd = 3)
    points(input$epsp, input$epsbeta, col = "red")
  })
  #
  #
  #
  #
  #
  #-----------------------------------------------
  #
  #
  #
  #
  # ODEs
  # Parameters that are calculated
  #  p
  output$pValue <- renderPrint({pVal <- input$B * input$delt;
  cat(paste("\\(p \\)", "=", "\\(B \\delta \\)", "=", pVal))})
  #  beta
  output$betaValue <- renderPrint({betVal <- input$R0 * input$c / ((input$mu * input$B - input$R0)*input$T0);
  cat(paste("\\(\\beta\\)", "=", "\\(\\frac{R_0 c}{(\\mu B - R_0) T_0}\\)", "=", format(betVal, digits = 2, scientific = TRUE) ))})
  
  # Set of equations to be solved
  mdl <- function(t, state, parms){
    with(as.list(c(state, parms)), {
      # Rates of change
      de <- (1-epsbeta)*bet*targetCells*virions - k*eclipseCells; # cells in eclipse phase
      di <- k*eclipseCells - delt*infectedCells;   # infected cells
      dv <- mu*(1-epsp)*p*infectedCells - c * virions - (1-epsbeta)*bet*targetCells*virions; # virions
      dw <- (1-mu)*(1-epsp)*p*infectedCells - c * virionsnoninf; # non infectious virions
      dt <- - (1-epsbeta)*bet*targetCells*virions # target cells
      # Return rates of change
      list(c(de, di, dv, dw, dt))
    })
  }
  
  # Other parameters
  tf <- 40 # Final time
  times <- seq(0, tf, by = 0.01) 
  
  # colors and other graphical parameters
  library(RColorBrewer)
  cols <- brewer.pal(6, "Dark2")
  colV <- cols[4]
  colW <- cols[6]
  colT <- cols[1]
  colE <- cols[3]
  colI <- cols[2]
  lwds <- 2
  
  
  output$ODEplot <- renderPlot({
    # Initial conditions
    state <- c(eclipseCells = 0,
               infectedCells = 0,
               virions = input$V0, 
               virionsnoninf = 0,
               targetCells = input$T0)
    
    # Model parameters
    tmp <- c(k = input$k, 
             delt = input$delt, 
             c = input$c, 
             p = input$B * input$delt, 
             mu = input$mu,
             R0 = input$R0, 
             epsp = input$epsp, 
             epsbeta = input$epsbeta)
    # Compute beta out of the parameters
    bet <- with(as.list(c(tmp, state)), R0 * c / ((mu * p/delt - R0) *targetCells))
    # All parms
    parms <- c(tmp, bet = bet)
    # Solve the model
    out <- ode(y = state, times = times, func = mdl, parms = parms)
    
    # Plotting        
    par(las = 1)
    par(mar = c(4, 6, 5, 6))
    plot(out[-1, "time"], out[-1, "eclipseCells"], ylim = c(min(out[-1, -1]), max(out[-1, -1])), type = "l", log = "y", xlab = "Time", ylab = "Abundances", col = colE, lwd = lwds)
    lines(out[-1, "time"], out[-1, "infectedCells"], col = colI, lwd = lwds)
    lines(out[, "time"], out[, "virions"], col = colV, lwd = lwds)
    lines(out[, "time"], out[, "virionsnoninf"], col = colW, lwd = lwds)
    lines(out[, "time"], out[, "targetCells"], col = colT, lwd = lwds)
    axis(4)
    legend(x = tf, xjust = 1, y = max(out[, -1]), legend = c("eclipse cells", "infected cells", "virions, inf", "virions, non inf", "target cells"), col = c(colE, colI, colV, colW, colT), lwd = lwds)
    title(main = "Within-host dynamics\n  ")
    
  })
  
  
}

# Run the application 
shinyApp(ui = ui, server = server)
