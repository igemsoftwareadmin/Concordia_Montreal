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

library(edgeR)
library(dplyr)

#Reformatting output from featureCount

counts <- read.delim("raw_counts.tabular", row.names = 1)
genes <- rownames(counts)
counts <- na.omit(sapply(counts, as.numeric))
rownames(counts) <- genes[-1]
d0 <- DGEList(counts)


#Adding Normalizing factors
d0 <- calcNormFactors(d0)

#filtering low expressed genes
cutoff <- 1
drop <- which(apply(cpm(d0), 1, max) < cutoff)
d <- d0[-drop,]
dim(d)

#Setting up factor names
gravity <- append(rep("MG", 4), rep("NG",4))
growth.phase <- c("exp", "exp", "sta", "sta", "exp", "exp","sta", "sta")

group <- interaction(gravity, growth.phase)

#Checking clustering
plotMDS(d, col = as.numeric(group))


#Voom and modeling
mm <- model.matrix(~0 + group)
y <- voom(d, mm, plot = TRUE) #looks okay

fit <- lmFit(y, mm)
exp.Contrast <- makeContrasts(groupMG.exp - groupNG.exp , levels = colnames(coef(fit)))
fit2 <- contrasts.fit(fit, exp.Contrast)
fit2 <- eBayes(fit2)
tT.exp <- topTable(fit2, n = Inf, adjust.method = "fdr")


#getting annotations
anno <- rtracklayer::import("ecoli_nissle_1917.gtf")

anno  <-  anno %>% as.data.frame %>% filter(type == "exon") %>% select(-seqnames, -source, -score, -phase)
vmatch <- match(rownames(tT.exp),anno$gene_id)

vmatch_id <- anno$gene_name[vmatch]
tT.exp <- tT.exp %>% mutate(Gene.Symbol = vmatch_id, Platform.ORF = rownames(tT.exp)) %>% na.omit()
write.csv(tT.exp, file = "datasets/GSE147272_Ecol/GSE147272_exponential.growth.csv")

#now for stationary phase
sta.Contrast <- makeContrasts(groupMG.sta - groupNG.sta , levels = colnames(coef(fit)))
fit3 <- contrasts.fit(fit, sta.Contrast)
fit3 <- eBayes(fit3)
tT.sta <- topTable(fit3, n = Inf, adjust.method = "fdr")

vmatch <- match(rownames(tT.sta),anno$gene_id)

vmatch_id <- anno$gene_name[vmatch]
tT.sta <- tT.sta %>% mutate(Gene.Symbol = vmatch_id, Platform.ORF = rownames(tT.sta)) %>% na.omit()
write.csv(tT.sta, file = "datasets/GSE147272_Ecol/GSE147272_stationary.growth.csv")

#getting metadata
mdata <- GEOquery::getGEO("GSE147272")
mdata <- mdata$GSE147272_series_matrix.txt.gz

source("microarray_functions.R")
metaName <- "datasets/GSE147272_Ecol/GSE147272_meta"
strain <- "Nissle_1917"

gselist <- list(list(GSE = mdata[,c(1,2,5,6)]), list(GSE = mdata[,c(3,4,7,8)]))
metalabels <- c("exponential.growth", "stationary.growth")
extractMetaData(gse_groups = gselist, filename = metaName, microgravity_type = M.TYPE$RCCS, metaLabels = metalabels, strain = strain)
