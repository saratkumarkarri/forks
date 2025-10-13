#!/usr/bin/env python3
"""
Cloud Native Qumulo Terraform IAM Permissions Tester

This script tests all IAM permissions required for deploying the Cloud Native Qumulo
solution using Terraform. It validates both persistent storage and main cluster
deployment permissions without making any actual changes to your AWS environment.

Requirements:
    pip install boto3 colorama tabulate

Usage:
    python iam_permissions_tester.py [--profile PROFILE] [--region REGION] [--test-type TYPE]
"""

import boto3
import json
import sys
import argparse
from typing import Dict, List, Tuple, Optional
from colorama import init, Fore, Style
from tabulate import tabulate
from botocore.exceptions import ClientError, NoCredentialsError
import time

# Initialize colorama for cross-platform colored output
init(autoreset=True)

class IAMPermissionsTester:
    def __init__(self, profile: Optional[str] = None, region: str = 'us-west-2'):
        """Initialize the IAM permissions tester."""
        self.region = region
        self.profile = profile
        self.session = self._create_session()
        self.iam_client = self.session.client('iam', region_name=region)
        self.sts_client = self.session.client('sts', region_name=region)
        self.current_user_arn = None
        self.test_results = []
        
    def _create_session(self) -> boto3.Session:
        """Create boto3 session with optional profile."""
        try:
            if self.profile:
                return boto3.Session(profile_name=self.profile)
            return boto3.Session()
        except Exception as e:
            print(f"{Fore.RED}Error creating AWS session: {e}")
            sys.exit(1)
            
    def get_current_user_info(self) -> Dict:
        """Get current user/role information."""
        try:
            response = self.sts_client.get_caller_identity()
            self.current_user_arn = response.get('Arn')
            return {
                'account': response.get('Account'),
                'user_id': response.get('UserId'), 
                'arn': response.get('Arn')
            }
        except Exception as e:
            print(f"{Fore.RED}Error getting caller identity: {e}")
            sys.exit(1)

    def test_permissions_simulation(self, service: str, actions: List[str], resources: List[str] = None) -> Dict:
        """Test permissions using IAM policy simulation."""
        if resources is None:
            resources = ['*']
            
        results = {'passed': [], 'failed': [], 'errors': []}
        
        for action in actions:
            try:
                # Use simulate_principal_policy to test permissions
                response = self.iam_client.simulate_principal_policy(
                    PolicySourceArn=self.current_user_arn,
                    ActionNames=[action],
                    ResourceArns=resources
                )
                
                for eval_result in response.get('EvaluationResults', []):
                    decision = eval_result.get('EvalDecision')
                    if decision == 'allowed':
                        results['passed'].append(action)
                    else:
                        failure_reason = eval_result.get('EvalDecisionDetails', {})
                        results['failed'].append({
                            'action': action,
                            'decision': decision,
                            'reason': failure_reason
                        })
                        
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code == 'InvalidUserID.NotFound':
                    # Try alternative method for roles
                    results['errors'].append({
                        'action': action,
                        'error': 'Cannot simulate for this principal type',
                        'suggestion': 'Manual verification required'
                    })
                else:
                    results['errors'].append({
                        'action': action,
                        'error': str(e),
                        'suggestion': 'Check AWS credentials and permissions'
                    })
            except Exception as e:
                results['errors'].append({
                    'action': action,
                    'error': str(e),
                    'suggestion': 'Unexpected error occurred'
                })
                
        return results

    def test_basic_access(self) -> bool:
        """Test basic AWS access and IAM permissions."""
        print(f"{Fore.CYAN}Testing basic AWS access...")
        
        try:
            # Test STS access
            caller_info = self.get_current_user_info()
            print(f"{Fore.GREEN}✓ AWS Access confirmed")
            print(f"  Account: {caller_info['account']}")
            print(f"  ARN: {caller_info['arn']}")
            
            # Test IAM read access
            self.iam_client.list_users(MaxItems=1)
            print(f"{Fore.GREEN}✓ IAM read access confirmed")
            return True
            
        except NoCredentialsError:
            print(f"{Fore.RED}✗ No AWS credentials found")
            print("Please configure AWS credentials using:")
            print("  - aws configure")
            print("  - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)")
            print("  - IAM role (if running on EC2)")
            return False
        except ClientError as e:
            print(f"{Fore.RED}✗ AWS access error: {e}")
            return False

    def test_core_ec2_permissions(self) -> Dict:
        """Test EC2 permissions required for deployment."""
        print(f"\n{Fore.CYAN}Testing Core EC2 Permissions...")
        
        ec2_actions = [
            'ec2:DescribeInstances',
            'ec2:DescribeInstanceTypes',
            'ec2:DescribeInstanceAttribute',
            'ec2:DescribeImages',
            'ec2:DescribeVpcs',
            'ec2:DescribeSubnets',
            'ec2:DescribeSecurityGroups',
            'ec2:DescribeVolumes',
            'ec2:DescribeSnapshots',
            'ec2:DescribeKeyPairs',
            'ec2:DescribeAvailabilityZones',
            'ec2:DescribeVpcEndpoints',
            'ec2:RunInstances',
            'ec2:TerminateInstances',
            'ec2:StopInstances',
            'ec2:StartInstances',
            'ec2:RebootInstances',
            'ec2:CreateVolume',
            'ec2:AttachVolume',
            'ec2:DetachVolume',
            'ec2:DeleteVolume',
            'ec2:ModifyInstanceAttribute',
            'ec2:CreateSecurityGroup',
            'ec2:DeleteSecurityGroup',
            'ec2:AuthorizeSecurityGroupIngress',
            'ec2:AuthorizeSecurityGroupEgress',
            'ec2:RevokeSecurityGroupIngress',
            'ec2:RevokeSecurityGroupEgress',
            'ec2:CreateTags',
            'ec2:DeleteTags'
        ]
        
        return self.test_permissions_simulation('ec2', ec2_actions)

    def test_core_s3_permissions(self) -> Dict:
        """Test S3 permissions required for deployment."""
        print(f"\n{Fore.CYAN}Testing Core S3 Permissions...")
        
        s3_actions = [
            's3:CreateBucket',
            's3:DeleteBucket',
            's3:ListBucket',
            's3:GetBucketLocation',
            's3:GetBucketVersioning',
            's3:GetBucketAcl',
            's3:GetBucketPolicy',
            's3:PutBucketPolicy',
            's3:DeleteBucketPolicy',
            's3:GetBucketLogging',
            's3:PutBucketLogging',
            's3:GetBucketTagging',
            's3:PutBucketTagging',
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:GetObjectVersion',
            's3:DeleteObjectVersion'
        ]
        
        # Test with Qumulo-specific resource patterns
        qumulo_resources = [
            'arn:aws:s3:::*qumulo*',
            'arn:aws:s3:::*qumulo*/*',
            'arn:aws:s3:::*qps*',
            'arn:aws:s3:::*qps*/*'
        ]
        
        return self.test_permissions_simulation('s3', s3_actions, qumulo_resources)

    def test_core_iam_permissions(self) -> Dict:
        """Test IAM permissions required for deployment."""
        print(f"\n{Fore.CYAN}Testing Core IAM Permissions...")
        
        iam_actions = [
            'iam:CreateRole',
            'iam:DeleteRole',
            'iam:GetRole',
            'iam:ListRoles',
            'iam:PassRole',
            'iam:CreateInstanceProfile',
            'iam:DeleteInstanceProfile',
            'iam:GetInstanceProfile',
            'iam:AddRoleToInstanceProfile',
            'iam:RemoveRoleFromInstanceProfile',
            'iam:AttachRolePolicy',
            'iam:DetachRolePolicy',
            'iam:CreatePolicy',
            'iam:DeletePolicy',
            'iam:GetPolicy',
            'iam:GetPolicyVersion',
            'iam:ListPolicyVersions',
            'iam:PutRolePolicy',
            'iam:DeleteRolePolicy',
            'iam:GetRolePolicy',
            'iam:ListRolePolicies',
            'iam:TagRole',
            'iam:UntagRole',
            'iam:ListRoleTags'
        ]
        
        return self.test_permissions_simulation('iam', iam_actions)

    def test_ssm_permissions(self) -> Dict:
        """Test Systems Manager permissions."""
        print(f"\n{Fore.CYAN}Testing Systems Manager Permissions...")
        
        ssm_actions = [
            'ssm:GetParameter',
            'ssm:GetParameters',
            'ssm:PutParameter',
            'ssm:DeleteParameter',
            'ssm:GetParameterHistory'
        ]
        
        ssm_resources = ['arn:aws:ssm:*:*:parameter/qumulo/*']
        
        return self.test_permissions_simulation('ssm', ssm_actions, ssm_resources)

    def test_secrets_manager_permissions(self) -> Dict:
        """Test Secrets Manager permissions."""
        print(f"\n{Fore.CYAN}Testing Secrets Manager Permissions...")
        
        secrets_actions = [
            'secretsmanager:CreateSecret',
            'secretsmanager:DeleteSecret',
            'secretsmanager:DescribeSecret',
            'secretsmanager:GetSecretValue',
            'secretsmanager:PutSecretValue',
            'secretsmanager:UpdateSecret',
            'secretsmanager:TagResource',
            'secretsmanager:UntagResource'
        ]
        
        secrets_resources = ['arn:aws:secretsmanager:*:*:secret:qumulo-*']
        
        return self.test_permissions_simulation('secretsmanager', secrets_actions, secrets_resources)

    def test_cloudwatch_permissions(self) -> Dict:
        """Test CloudWatch permissions."""
        print(f"\n{Fore.CYAN}Testing CloudWatch Permissions...")
        
        cloudwatch_actions = [
            'logs:CreateLogGroup',
            'logs:DeleteLogGroup',
            'logs:DescribeLogGroups',
            'logs:PutRetentionPolicy',
            'logs:TagLogGroup',
            'logs:UntagLogGroup',
            'resource-groups:CreateGroup',
            'resource-groups:DeleteGroup',
            'resource-groups:GetGroup',
            'resource-groups:UpdateGroup',
            'resource-groups:Tag',
            'resource-groups:Untag'
        ]
        
        return self.test_permissions_simulation('cloudwatch', cloudwatch_actions)

    def test_route53_resolver_permissions(self) -> Dict:
        """Test Route 53 Resolver permissions (conditional)."""
        print(f"\n{Fore.CYAN}Testing Route 53 Resolver Permissions (Optional)...")
        
        route53_actions = [
            'route53resolver:CreateResolverEndpoint',
            'route53resolver:DeleteResolverEndpoint',
            'route53resolver:GetResolverEndpoint',
            'route53resolver:ListResolverEndpoints',
            'route53resolver:CreateResolverRule',
            'route53resolver:DeleteResolverRule',
            'route53resolver:GetResolverRule',
            'route53resolver:ListResolverRules',
            'route53resolver:AssociateResolverRule',
            'route53resolver:DisassociateResolverRule',
            'route53resolver:TagResource',
            'route53resolver:UntagResource'
        ]
        
        return self.test_permissions_simulation('route53resolver', route53_actions)

    def test_elb_permissions(self) -> Dict:
        """Test Elastic Load Balancing permissions (conditional)."""
        print(f"\n{Fore.CYAN}Testing Elastic Load Balancing Permissions (Optional)...")
        
        elb_actions = [
            'elasticloadbalancing:CreateLoadBalancer',
            'elasticloadbalancing:DeleteLoadBalancer',
            'elasticloadbalancing:DescribeLoadBalancers',
            'elasticloadbalancing:DescribeLoadBalancerAttributes',
            'elasticloadbalancing:ModifyLoadBalancerAttributes',
            'elasticloadbalancing:CreateTargetGroup',
            'elasticloadbalancing:DeleteTargetGroup',
            'elasticloadbalancing:DescribeTargetGroups',
            'elasticloadbalancing:DescribeTargetGroupAttributes',
            'elasticloadbalancing:ModifyTargetGroupAttributes',
            'elasticloadbalancing:CreateListener',
            'elasticloadbalancing:DeleteListener',
            'elasticloadbalancing:DescribeListeners',
            'elasticloadbalancing:RegisterTargets',
            'elasticloadbalancing:DeregisterTargets',
            'elasticloadbalancing:DescribeTargetHealth',
            'elasticloadbalancing:AddTags',
            'elasticloadbalancing:RemoveTags'
        ]
        
        return self.test_permissions_simulation('elasticloadbalancing', elb_actions)

    def test_kms_permissions(self) -> Dict:
        """Test KMS permissions (conditional - only needed if using customer-managed keys)."""
        print(f"\n{Fore.CYAN}Testing KMS Permissions (Optional - only if using customer-managed keys)...")
        
        kms_actions = [
            'kms:DescribeKey',
            'kms:GetKeyPolicy',
            'kms:ListKeys',
            'kms:CreateGrant',
            'kms:RevokeGrant'
        ]
        
        return self.test_permissions_simulation('kms', kms_actions)

    def test_terraform_state_permissions(self) -> Dict:
        """Test Terraform state management permissions."""
        print(f"\n{Fore.CYAN}Testing Terraform State Management Permissions...")
        
        # S3 backend permissions
        s3_state_actions = [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:ListBucket'
        ]
        
        # Example state bucket - users should modify this for their specific setup
        state_resources = [
            'arn:aws:s3:::dackss3-dev/tf-state/*',
            'arn:aws:s3:::dackss3-dev'
        ]
        
        s3_results = self.test_permissions_simulation('s3-state', s3_state_actions, state_resources)
        
        # DynamoDB locking permissions
        dynamodb_actions = [
            'dynamodb:GetItem',
            'dynamodb:PutItem',
            'dynamodb:DeleteItem'
        ]
        
        dynamodb_resources = ['arn:aws:dynamodb:*:*:table/terraform-state']
        dynamodb_results = self.test_permissions_simulation('dynamodb', dynamodb_actions, dynamodb_resources)
        
        return {
            's3_backend': s3_results,
            'dynamodb_locking': dynamodb_results
        }

    def print_results_summary(self, results: Dict, category: str):
        """Print formatted results summary."""
        print(f"\n{Fore.YELLOW}{'='*60}")
        print(f"{Fore.YELLOW}{category.upper()} RESULTS SUMMARY")
        print(f"{Fore.YELLOW}{'='*60}")
        
        table_data = []
        
        # Handle nested results structure
        if isinstance(list(results.values())[0], dict) and 'passed' in list(results.values())[0]:
            # Direct service results
            service_results = results
        else:
            # Nested results (like terraform state)
            flattened_results = {}
            for sub_category, sub_results in results.items():
                if isinstance(sub_results, dict) and 'passed' in sub_results:
                    flattened_results[sub_category] = sub_results
                else:
                    # Further nested
                    for service, service_results in sub_results.items():
                        flattened_results[f"{sub_category}_{service}"] = service_results
            service_results = flattened_results
        
        for service, service_results in service_results.items():
            passed_count = len(service_results.get('passed', []))
            failed_count = len(service_results.get('failed', []))
            error_count = len(service_results.get('errors', []))
            total_count = passed_count + failed_count + error_count
            
            if total_count > 0:
                success_rate = f"{(passed_count/total_count)*100:.1f}%"
                status = f"{Fore.GREEN}✓" if failed_count == 0 and error_count == 0 else f"{Fore.RED}✗"
            else:
                success_rate = "N/A"
                status = f"{Fore.YELLOW}?"
                
            table_data.append([
                f"{status} {service.upper()}",
                passed_count,
                failed_count, 
                error_count,
                success_rate
            ])
            
        headers = ["Service", "Passed", "Failed", "Errors", "Success Rate"]
        print(tabulate(table_data, headers=headers, tablefmt="grid"))

    def print_detailed_failures(self, results: Dict, category: str):
        """Print detailed information about failed permissions."""
        print(f"\n{Fore.RED}DETAILED FAILURE ANALYSIS - {category.upper()}")
        print(f"{Fore.RED}{'='*60}")
        
        has_failures = False
        
        # Handle nested results structure
        if isinstance(list(results.values())[0], dict) and 'passed' in list(results.values())[0]:
            # Direct service results
            service_results = results
        else:
            # Nested results (like terraform state)
            flattened_results = {}
            for sub_category, sub_results in results.items():
                if isinstance(sub_results, dict) and 'passed' in sub_results:
                    flattened_results[sub_category] = sub_results
                else:
                    # Further nested
                    for service, service_res in sub_results.items():
                        flattened_results[f"{sub_category}_{service}"] = service_res
            service_results = flattened_results
        
        for service, service_result in service_results.items():
            failed_actions = service_result.get('failed', [])
            error_actions = service_result.get('errors', [])
            
            if failed_actions or error_actions:
                has_failures = True
                print(f"\n{Fore.CYAN}{service.upper()} Service Issues:")
                
                for failure in failed_actions:
                    action = failure.get('action', 'Unknown')
                    decision = failure.get('decision', 'Unknown')
                    print(f"  {Fore.RED}✗ {action}")
                    print(f"    Decision: {decision}")
                    
                for error in error_actions:
                    action = error.get('action', 'Unknown')
                    error_msg = error.get('error', 'Unknown error')
                    suggestion = error.get('suggestion', 'No suggestion available')
                    print(f"  {Fore.YELLOW}⚠ {action}")
                    print(f"    Error: {error_msg}")
                    print(f"    Suggestion: {suggestion}")
                    
        if not has_failures:
            print(f"{Fore.GREEN}No permission failures detected in {category}!")

    def generate_iam_policy(self, all_results: Dict) -> Dict:
        """Generate IAM policy based on failed permissions."""
        print(f"\n{Fore.CYAN}Generating IAM Policy for Missing Permissions...")
        
        missing_actions = []
        
        for category_name, category_results in all_results.items():
            # Handle nested results structure
            if isinstance(list(category_results.values())[0], dict) and 'passed' in list(category_results.values())[0]:
                # Direct service results
                service_results = category_results
            else:
                # Nested results
                flattened_results = {}
                for sub_category, sub_results in category_results.items():
                    if isinstance(sub_results, dict) and 'passed' in sub_results:
                        flattened_results[sub_category] = sub_results
                    else:
                        # Further nested
                        for service, service_res in sub_results.items():
                            flattened_results[f"{sub_category}_{service}"] = service_res
                service_results = flattened_results
            
            for service_result in service_results.values():
                for failure in service_result.get('failed', []):
                    action = failure.get('action')
                    if action and action not in missing_actions:
                        missing_actions.append(action)
                        
        if not missing_actions:
            print(f"{Fore.GREEN}No missing permissions found!")
            return {}
            
        # Group actions by service for better policy organization
        service_actions = {}
        for action in missing_actions:
            service = action.split(':')[0]
            if service not in service_actions:
                service_actions[service] = []
            service_actions[service].append(action)
        
        statements = []
        for service, actions in service_actions.items():
            statement = {
                "Effect": "Allow",
                "Action": actions,
                "Resource": "*"
            }
            statements.append(statement)
            
        policy = {
            "Version": "2012-10-17",
            "Statement": statements
        }
        
        print(f"\n{Fore.YELLOW}IAM Policy for Missing Permissions:")
        print(json.dumps(policy, indent=2))
        
        return policy

    def run_full_test(self, test_type: str = 'all') -> Dict:
        """Run the complete permissions test suite."""
        print(f"{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}CLOUD NATIVE QUMULO TERRAFORM IAM PERMISSIONS TESTER")
        print(f"{Fore.CYAN}{'='*70}")
        
        # Test basic access first
        if not self.test_basic_access():
            return {}
            
        all_results = {}
        
        if test_type in ['all', 'core']:
            # Test core permissions
            print(f"\n{Fore.YELLOW}Testing Core AWS Service Permissions...")
            
            ec2_results = self.test_core_ec2_permissions()
            s3_results = self.test_core_s3_permissions()
            iam_results = self.test_core_iam_permissions()
            
            core_results = {
                'ec2': ec2_results,
                's3': s3_results,
                'iam': iam_results
            }
            all_results['core_services'] = core_results
            self.print_results_summary(core_results, "Core AWS Services")
            
        if test_type in ['all', 'additional']:
            # Test additional service permissions
            print(f"\n{Fore.YELLOW}Testing Additional Service Permissions...")
            
            ssm_results = self.test_ssm_permissions()
            secrets_results = self.test_secrets_manager_permissions()
            cloudwatch_results = self.test_cloudwatch_permissions()
            
            additional_results = {
                'ssm': ssm_results,
                'secretsmanager': secrets_results,
                'cloudwatch': cloudwatch_results
            }
            all_results['additional_services'] = additional_results
            self.print_results_summary(additional_results, "Additional Services")
            
        if test_type in ['all', 'conditional']:
            # Test conditional permissions
            print(f"\n{Fore.YELLOW}Testing Conditional Permissions...")
            
            route53_results = self.test_route53_resolver_permissions()
            elb_results = self.test_elb_permissions()
            kms_results = self.test_kms_permissions()
            
            conditional_results = {
                'route53resolver': route53_results,
                'elasticloadbalancing': elb_results,
                'kms': kms_results
            }
            all_results['conditional_services'] = conditional_results
            self.print_results_summary(conditional_results, "Conditional Services")
            
        if test_type in ['all', 'state']:
            # Test Terraform state permissions
            print(f"\n{Fore.YELLOW}Testing Terraform State Management Permissions...")
            
            state_results = self.test_terraform_state_permissions()
            all_results['terraform_state'] = state_results
            self.print_results_summary(state_results, "Terraform State Management")
            
        # Print detailed failure information
        for category, results in all_results.items():
            self.print_detailed_failures(results, category)
            
        # Generate IAM policy for missing permissions
        if all_results:
            self.generate_iam_policy(all_results)
            
        # Print final summary
        total_categories = len(all_results)
        categories_with_failures = 0
        
        for category_results in all_results.values():
            # Handle nested structure
            if isinstance(list(category_results.values())[0], dict) and 'passed' in list(category_results.values())[0]:
                service_results = category_results
            else:
                flattened_results = {}
                for sub_category, sub_results in category_results.items():
                    if isinstance(sub_results, dict) and 'passed' in sub_results:
                        flattened_results[sub_category] = sub_results
                    else:
                        for service, service_res in sub_results.items():
                            flattened_results[f"{sub_category}_{service}"] = service_res
                service_results = flattened_results
            
            for service_result in service_results.values():
                if service_result.get('failed') or service_result.get('errors'):
                    categories_with_failures += 1
                    break
        
        print(f"\n{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}FINAL SUMMARY")
        print(f"{Fore.CYAN}{'='*70}")
        
        if categories_with_failures == 0:
            print(f"{Fore.GREEN}✓ All permission tests passed!")
            print(f"{Fore.GREEN}  Your role has sufficient permissions to deploy Cloud Native Qumulo.")
        else:
            print(f"{Fore.RED}✗ {categories_with_failures} service categories have permission issues")
            print(f"{Fore.YELLOW}  Review the detailed failure analysis above")
            print(f"{Fore.YELLOW}  Use the generated IAM policy to address missing permissions")
        
        print(f"\n{Fore.CYAN}Categories tested: {total_categories}")
        print(f"{Fore.CYAN}Categories with issues: {categories_with_failures}")
        print(f"{Fore.CYAN}{'='*70}")
        
        return all_results


def main():
    parser = argparse.ArgumentParser(description='Test IAM permissions for Cloud Native Qumulo Terraform deployment')
    parser.add_argument('--profile', help='AWS profile name to use')
    parser.add_argument('--region', default='us-west-2', help='AWS region (default: us-west-2)')
    parser.add_argument('--test-type', choices=['all', 'core', 'additional', 'conditional', 'state'], 
                       default='all', help='Type of permissions to test')
    
    args = parser.parse_args()
    
    try:
        tester = IAMPermissionsTester(profile=args.profile, region=args.region)
        results = tester.run_full_test(test_type=args.test_type)
        
        # Exit with appropriate code
        has_failures = False
        for category_results in results.values():
            # Handle nested structure for exit code determination
            if isinstance(list(category_results.values())[0], dict) and 'passed' in list(category_results.values())[0]:
                service_results = category_results
            else:
                flattened_results = {}
                for sub_category, sub_results in category_results.items():
                    if isinstance(sub_results, dict) and 'passed' in sub_results:
                        flattened_results[sub_category] = sub_results
                    else:
                        for service, service_res in sub_results.items():
                            flattened_results[f"{sub_category}_{service}"] = service_res
                service_results = flattened_results
            
            for service_result in service_results.values():
                if service_result.get('failed') or service_result.get('errors'):
                    has_failures = True
                    break
                    
        sys.exit(1 if has_failures else 0)
        
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"{Fore.RED}Unexpected error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()