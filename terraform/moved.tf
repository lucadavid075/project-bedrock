moved {
  from = module.eks.aws_eks_access_entry.this["cluster_creator"]
  to   = aws_eks_access_entry.cluster_admin
}

moved {
  from = module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]
  to   = aws_eks_access_policy_association.cluster_admin
}
