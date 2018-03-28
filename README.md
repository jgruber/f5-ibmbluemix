# f5-ibmbluemix
cloud-init based onboarding of TMOS Virtual Edition for IBM Cloud instances.

These instuctions are for the base onboarding of TMOS Virtual Edition in the IBM Cloud environemnt. Once TMOS devices are created in the cloud environment, both [f5-cloud-libs](https://github.com/F5Networks/f5-cloud-libs) and [f5-ansible](https://github.com/F5Networks/f5-ansible) libraries can be used to perform additional provisioning automation.

TMOS Virtual Editions can be launched with Virtual Hosts for performance under 1Gbps, and as instances running on Bare Metal hosts for performance in excess of 1Gbps. The process for onboarding TMOS Virtual Edition into IBM Cloud are detailed below.

# Launching TMOS Virtual Edition as a IBM Cloud Virtual Host

IBM Cloud offers the ability to order Virtual Hosts with various options and utilizations. The sizing of the virtual host will be dependant on which TMOS Virtual Edition you are creating in the IBM Cloud.

The proceedure for creating a TMOS Virtual Edition breaks into two stages:

### Steps Performed Once Per Each TMOS Virtual Edition Image Version

1. Obtain the TMOS Virtual Edition VHD Disk Images
2. Create Object Storage for the TMOS Disk Images
3. Upload TMOS Disk Images into Object Storage
3. Create a Disk Image from Object Storage

### Steps Performed When Launching Each TMOS Virutal Edition

1. Download and Customize Your cloud-init User Data File
2. Creating a TMOS Virtual Edition Virtual Machine

## Obtaining TMOS Virtual Edition VHD Disk Images

F5 TMOS Virtual Edition disk images can be obtained from [https://downloads.f5.com](https://downloads.f5.com). Please contact your account representatives if you have any questions about TMOS Virtual Edition licensing or download options.

**These cloud-init based templates are only intended for TMOS Virtual Edition version 13.1 or higher. The required cloud-init functionality is not available before TMOS Virtual Edition version 13.1. Do not attempt to use these templates with TMOS Virtual Editions prior to the 13.1 release.**

To determine which TMOS Virtual Edition you will need to properly support the F5 functionality and performance desired, the following guides have been prepared:

[Overview of BIG-IP VE image sizes](https://support.f5.com/csp/article/K14946)
[Overview of BIG-IP VE license and throughput limits](https://support.f5.com/csp/article/K14810)
[Environmental setup for evaluating performance on the BIG-IP Virtual Edition system](https://support.f5.com/csp/article/K17160)

Due to limitations with the virtualized networking, only TMOS Virtual Editions rated at or below 1Gbps throughput are supported as IBM Cloud Virtual Hosts. For performance rates greater than 1Gps, Bare Metal instances with the high-performance KVM virtual machine manager can be utilized.

IBM Cloud requires the use of the VHD disk image format for their Virtual Hosts. Please assure that you have downloaded the correct VHD TMOS Virtual Edition disk images.

To create a TMOS Virtual Editional instance as an IBM Cloud Virtual Host, you will be downloading the vhd disks labeled as `BIGIP-[version].[TMOS Edition].vhd.zip`. As an example for the LTM 1SLOT TMOS edition of TMOS version 13.1.0.3.0.0.5, you would download the `BIGIP-13.1.0.3.0.0.5.LTM_1SLOT.vhd.zip`.

The md5 hash for each TMOS Virtual edition zip archive is available and it is highly recommended that the hash be validated to assure the local download has completed successfully.

Once you have downloaded your TMOS Virtual Edition VHD disk image zip archive file, you will need to uncompress it. The download is maintained as a standard zip file archive and can be uncompressed with standard unzip utilities. *You will be uploading the uncompressed VHD image file, not the downloaded zip archive.*

## Creating Object Storage for the TMOS Disk Images

In order to make your TMOS Virtual Edition disk image available for use with an IBM Cloud Virtual Host, you must first make your TMOS Virtual Edition disk image available to the IBM Cloud internal image import system. This is done by creating a IBM Cloud Swift Object Storage container and uploading your TMOS Virtual Edition disk image  into the container. Documentation for using IBM Cloud Swift object storage can be found at the following links:

[IBM Cloud Storage - Object Storage](https://console.bluemix.net/docs/infrastructure/objectstorage-swift/index.html#getting-started-with-object-storage-openstack-swift)
[How do I access object storage by the command line?](http://knowledgelayer.softlayer.com/es/procedure/how-do-i-access-object-storage-command-line)

## Uploading TMOS Disk Images to Object Storage

The IBM Cloud web portal does not support the uploading of storage objects which are larger then 20M bytes. In order to upload your TMOS Virtual Edition VHD disk image, you will need to use one of the upload clients documented by IBM. Here are a few options:

[Connecting to Object Storage OpenStack Swift using Cyberduck](https://console.bluemix.net/docs/infrastructure/objectstorage-swift/connect-object-storage-using-cyberduck.html#connecting-to-object-storage-openstack-swift-using-cyberduck)
[Softlayer Github Repository - Bash and Python examples](https://softlayer.github.io/python/swiftUploader/)

## Creating a Disk Image from Object Storage

Once the TMOS Virtual Edition VHD disk image is uploaded into object storage, the Virtual Host image system can import it. Imported images can then be used to launch multiple TMOS Virtual Edition instances as Virtual Hosts. This step can be completed through the IBM Cloud web portal, CLI tools, or through the Soft Layer API.

[Importing an Image](https://console.bluemix.net/docs/infrastructure/image-templates/import-image.html#importing-an-image)

It is recommended that you use F5 Virtual Edition disk image naming convention when creating your images in the Object Storage service. As an example for the `BIGIP-13.1.0.3.0.0.5.LTM_1SLOT.vhd` image, the recommended Image name would be `BIGIP-13.1.0.3.0.0.5.LTM_1SLOT`. Following this suggestion will allow for future TMOS Virtual Edition images to be imported without confusion to naming collisions.

## Downloading and Customizing the cloud-init User Data File

F5 TMOS Networking utilizes the high-performance Traffic Management Microkernel (TMM) rather then standand server networking components. The IBM Cloud Virtual Host provisioning process is designed to create standard Linux and Windows based network configurations where as TMOS provisions TMM interfaces, VLANs, and Self-IPs. In order to accept the network configuration provided by the IBM Cloud Virtual Host provision system and transform that information into the appropriate TMM objects, a cloud-init onboarding process is utilized. Cloud-init is the industry standard for cloud serer onboarding and is supported in TMOS v13.1+.

This repository contains the cloud-init user_data file required to provision the IBM Cloud `Private and Public`, and `Private Only` networking models on TMOS Virtual Editions.

To obtain the user_data file for your TMOS Virtual Edition instance, download the [ibm_init_userdata.txt](https://raw.githubusercontent.com/jgruber/f5-ibmbluemix/master/ibm_init_userdata.txt) file from this repository.

### Customized Settings in the User Data File

The only customized setting in the user_data file are the values used for the built in `admin` and `root` passwords of your instance. All other provisioning artifacts, network settings, and SSH keys, are derived from the IBM Cloud settings.

Editing the downloaded `ibm_init_userdata.txt` file with your preferred text editor, change the `__TMOS_ADMIN_PASSWORD__` and `__TMOS_ROOT_PASSWORD__` fields in the file to your desired values for this specific TMOS Virtual Edition instances. Here is an example using the standard Unix `sed` editor.

```
sed -i -e "s/__TMOS_ADMIN_PASSWORD__/softlayer/g" ibm_init_userdata.txt
sed -i -e "s/__TMOS_ROOT_PASSWORD__/softlayer/g" ibm_init_userdata.txt
```

It is of note that the TMM Self-IPs are provisioned to `allow-all` services initialiatlly. This can be altered when other services and settings are provisioned in later stage orchestration. F5 supports later stage orchestration through the use of our [f5-ansible](https://github.com/F5Networks/f5-ansible) modules and [TMOS REST APIs](https://devcentral.f5.com/wiki/iControlREST.HomePage.ashx).

In addition, because there are multiple license activation options, TMOS license orchestration has also been deferred to later stage orchestration. F5 provides various license orchestration methods through both our [f5-cloud-libs](https://github.com/F5Networks/f5-cloud-libs) libraries and our [BIG-IQ APIs](https://devcentral.f5.com/wiki/BIGIQ.HowToSamples_license_member_management.ashx).

## Creating a TMOS Virtual Edition Virtual Machine

The IBM Cloud web portal will try to limit the size of the Virtual Host initial disk based on the size of the Image you imported. Because all the disk images are less than 25GB, the Virtual Host created using the Image through the port will only allow for 25GB disk images. The disk images sized for TMOS Virtual Edition are documented in the following article:

[Overview of BIG-IP VE image sizes](https://support.f5.com/csp/article/K14946)

and summarized in the table below for TMOS version 13.1

Image Type    |  Disk Size Required |
--- | --- |
LTM_1SLOT | 9GB
LTM | 40GB
ALL | 82GB
ALL_1SLOT | 60GB

What this effectively means is that your Virtual Host for all but LTM_1SLOT images must use a CLI or API client to create the Virtual Host with the appropriate disk size.



# Launching TMOS Virtual Edition on a IBM Cloud Bare Metal Host

The proceedure for creating a TMOS Virtual Edition for Bare Metal installation is as follows:

### Steps Perfomred When Launching Each TMOS Virutal Edition

1. Order the appropriate CentOS 7.x minimal Bare Metal host
2. Download your TMOS Virtual Edition QCOW disk image to your Bare Metal host
3. Download and Customize the TMOS Virtual Edition install script from this repo
4. Run the TMOS Virtual Edition install script

## Ordering a Bare Metal Server

The TMOS Virtual Edition install script assume the software packaging tools and packages associated with Red Hat Linux version 7. The installation script was tested with the IBM Cloud Bare Metal CentOS 7.x minimal OS install image.

It is assumed that the Bare Metal host has public network access in order to download the necessary packages for the high-performance KVM virtual machine manageer environment. In addition, the host must have access to the URLs specified in the installation script to download the TMOS Virtual Edition qcow2 disk image, KVM environment template, and the user_data file template. These files can be installed locally and referenced by `file://` URLs.

## Obtaining TMOS Virtual Edition QCOW Disk Images

F5 TMOS Virtual Edition disk images can be obtained from [https://downloads.f5.com](https://downloads.f5.com). Please contact your account representatives if you have any questions about TMOS Virtual Edition licensing or download options.

**These cloud-init based templates are only intended for TMOS Virtual Edition version 13.1 or higher. The required cloud-init functionality is not available before TMOS Virtual Edition version 13.1. Do not attempt to use these templates with TMOS Virtual Editions prior to the 13.1 release.**

To determine which TMOS Virtual Edition you will need to properly support the F5 functionality and performance, the following guides have been prepared:

[Overview of BIG-IP VE image sizes](https://support.f5.com/csp/article/K14946)
[Overview of BIG-IP VE license and throughput limits](https://support.f5.com/csp/article/K14810)

The KVM domain enviroment to launch your TMOS Virtual Edition has been templated to allow for ease in tuning. Without tuning, the provided KVM domain environment template supports TMOS Virtual Editions up to 5Gbps. This performance will be entirely dependant on the Bare Metal device ordered and should follow the guidlines found here:

[Environmental setup for evaluating performance on the BIG-IP Virtual Edition system](https://support.f5.com/csp/article/K17160)

The md5 hash for each TMOS Virtual edition zip archive is available and it is highly recommended that the hash be validated to assure the local download has completed successfully.

Once you have downloaded your TMOS Virtual Edition qcow2 disk image, you will need to uncompress it. The download is maintained as a standard zip file archive and can be uncompressed with standard unzip utilities. *You will be uploading the qcow2 image file, not the downloaded zip archive.* It is the qcow2 disk image from within the zip archive that will be downloading onto your Bare Metal host by the installation script.

## Downloading the TMOS Virtual Edition QCOW Disk Image to Your Host

Once you have downloaded the zip file archive from [https://downloads.f5.com](https://downloads.f5.com), use `scp` (secure copy) to upload the zip file to your IBM Cloud Bare Metal host. `ssh` into your host as the `root` user. 

Install the unzip utility from the standard repository:

``# yum install unzip
``

Unzip your zip file archive containing your TMOS Virtual Edition qcow2 disk image. As example:

``# unzip BIGIP-13.1.0.3.0.0.5.ALL_1SLOT.qcow2.zip``

Record the file location of the extracted qcow2 disk image for use in the next step. As example:

``/root/BIGIP-13.1.0.3.0.0.5.qcow2``

## Downloading the TMOS Virtual Edition Installation Script

To obtain the TMOS Virtual Edition installation script file, download the [ibmbm_tmos_ve_install.sh](https://raw.githubusercontent.com/jgruber/f5-ibmbluemix/master/ibmbm_tmos_ve_install.sh) file from this repository.

``# wget https://raw.githubusercontent.com/jgruber/f5-ibmbluemix/master/ibmbm_tmos_ve_install.sh``

``# vi ibmbm_tmos_ve_install.sh``

```
#### Settings ####

# TMOS Virtual edition well known account settings

TMOS_ADMIN_PASSWORD="ibmsoftlayer"
TMOS_ROOT_PASSWORD="ibmsoftlayer"

# Github repo and branch for KVM environment and user_data templates

REPO="jgruber"
BRANCH="master"

BIGIP_UNZIPPED_QCOW_IMAGE_URL="file:///tmp/BIGIP-13.1.0.3.0.0.5.qcow2"
TMOS_VE_DOMAIN_TEMPLATE="https://raw.githubusercontent.com/$REPO/f5-ibmbluemix/$BRANCH/ve_domain_xml.tmpl"
USER_DATA_URL="https://raw.githubusercontent.com/$REPO/f5-ibmbluemix/$BRANCH/ibm_init_userdata.txt"

#### End Settings ####

```

## Running the TMOS Virtual Edition Installation Script

Execute the TMOS Virtual Edition installation script.

``# bash ibmbm_tmos_ve_install.sh``

The Bare Metal host will reboot after installation and the network addresses previously allocated to the Bare Metal host by the IBM Cloud provisioning process will now owned by the TMOS Virtual Edition running on the host. The only access to the Bare Metal host operating system will be through the remote console for the Bare Metal host. The Bare Metal host is simply functioning as a compute host for the TMOS Virtual Edition.

If at any point in this process you experience difficulty, simply reload the OS for the Bare Metal device and start over.



